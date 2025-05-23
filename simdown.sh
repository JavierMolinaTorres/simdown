#!/bin/bash
# -----------------------------------------------------------------------------
# simdown.sh - Simula un apagado de servidor desconectando la red temporalmente
# Autor: Javier Molina + ChatGPT
#
# FUNCIONALIDAD:
#   - Desactiva una interfaz de red durante un tiempo determinado simulando caída.
#   - Guarda y restaura configuración IP y rutas.
#   - Envía un aviso por correo (si está configurado y disponible).
#
# NOTAS SOBRE CORREO:
#   - Este script intenta enviar un correo si el binario `mail` está disponible.
#   - No se depende de `msmtp`, `sendemail` u otros agentes externos.
#   - Para que el envío funcione:
#       1. Debe estar instalado `mailutils` o equivalente (`mail` debe existir).
#       2. Debe estar correctamente configurado el MTA local (Postfix, Exim...).
#       3. El remitente definido en `email_from` debe estar autorizado si el MTA lo requiere.
#   - Si `mail` no está disponible, se notificará en el log y el script continuará.
#   - El script espera 60 segundos después del envío para garantizar la entrega
#     antes de cortar la red.
#
#   Recomendación: en entornos de producción, asegúrate de que `mailutils` esté instalado:
#     apt install mailutils
# -----------------------------------------------------------------------------

set -e

# CONFIGURACIÓN POR DEFECTO
duration=300  # segundos por defecto
iface=""
logfile="/var/log/simdown.log"
preview=false
send_email=true
email_to="javier.molina@csic.es"
email_from="serveis.dlgca@dicat.csic.es"   # remitente autorizado
email_subject="[simdown] Aviso de blackout de red"

# FUNCIONES
show_help() {
  echo -e "\nUso: $0 [-i interfaz] [-t segundos] [--preview] [--log archivo.log] [--email correo]"
  echo -e "\nOpciones:"
  echo "  -i, --interface    Nombre de la interfaz de red (ej: eth0, ens33). Si no se indica, se detecta automáticamente."
  echo "  -t, --time         Duración de la \"desaparición\" en segundos (por defecto 300)"
  echo "  --log archivo     Archivo de log (por defecto $logfile)"
  echo "  --email correo    Dirección de correo para avisos"
  echo "  --no-email        No enviar avisos por correo"
  echo "  --preview         Muestra lo que se haría sin ejecutarlo"
  echo "  -h, --help         Muestra esta ayuda"
  exit 0
}

log() {
  echo "[$(date +'%F %T')] $1" | tee -a "$logfile"
}

send_mail() {
  if [[ "$send_email" == true ]]; then
    if command -v mail > /dev/null; then
      echo -e "$1" | mail -s "$email_subject" -r "$email_from" "$email_to" || log "[WARN] No se pudo enviar correo"
    else
      log "[INFO] Comando 'mail' no disponible, no se enviará correo."
    fi
  fi
}

get_default_iface() {
  ip route get 8.8.8.8 | grep -oP 'dev \K[^ ]+' | head -n 1
}

backup_network_state() {
  mkdir -p /tmp/simdown-backup
  ip addr show "$iface" > "/tmp/simdown-backup/${iface}_addr.bak"
  ip route show > "/tmp/simdown-backup/${iface}_route.bak"
  log "Backup de IP y rutas guardado en /tmp/simdown-backup/"
}

restore_network_state() {
  log "Restaurando configuración de red de $iface..."

  if command -v ifdown >/dev/null && command -v ifup >/dev/null && grep -q "iface $iface" /etc/network/interfaces; then
    log "Usando ifdown/ifup para restaurar interfaz $iface"
    ifdown "$iface" || true
    sleep 2
    ifup "$iface"
  elif command -v netplan >/dev/null && ls /etc/netplan/*.yaml &>/dev/null; then
    log "Usando netplan apply para restaurar configuración"
    netplan apply
  else
    log "Restauración manual de IP desde backup..."
    ip addr flush dev "$iface"
    grep 'inet ' "/tmp/simdown-backup/${iface}_addr.bak" | awk '{print $2}' | while read -r ipcidr; do
      ip addr add "$ipcidr" dev "$iface"
    done
    ip route flush dev "$iface"
    while read -r line; do
      ip route add $line
    done < "/tmp/simdown-backup/${iface}_route.bak"
  fi

  sleep 2
  log "Verificando conectividad con gateway..."

  gw=$(grep '^default' "/tmp/simdown-backup/${iface}_route.bak" | awk '{print $3}')
  if [[ -n "$gw" ]]; then
    if ping -c 2 -W 2 "$gw" > /dev/null; then
      log "✅ Gateway $gw accesible tras restauración."
    else
      log "❌ ERROR: No se puede alcanzar el gateway $gw tras la restauración."
    fi
  else
    log "[INFO] No se detectó ruta por defecto en el backup, no se pudo verificar el gateway."
  fi
}

# PARSEADOR DE ARGUMENTOS
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--interface)
      iface="$2"; shift 2;;
    -t|--time)
      duration="$2"; shift 2;;
    --log)
      logfile="$2"; shift 2;;
    --email)
      email_to="$2"; shift 2;;
    --no-email)
      send_email=false; shift;;
    --preview)
      preview=true; shift;;
    -h|--help)
      show_help;;
    *)
      echo "Opción desconocida: $1"; show_help;;
  esac
done

# DETECTAR INTERFAZ ACTIVA SI NO SE INDICA
if [[ -z "$iface" ]]; then
  iface=$(get_default_iface)
  if [[ -z "$iface" ]]; then
    echo "No se pudo detectar la interfaz activa. Usa -i para especificarla."
    exit 1
  fi
  log "Interfaz detectada automáticamente: $iface"
fi

# MODO PREVIEW
if [[ "$preview" == true ]]; then
  echo "--- Modo PREVIEW ---"
  echo "Interfaz a desconectar: $iface"
  echo "Duración: $duration segundos"
  echo "Log: $logfile"
  echo "Correo destino: $email_to (desde: $email_from)"
  echo "Comandos que se ejecutarían:"
  echo "  ip link set $iface down"
  echo "  sleep $duration"
  echo "  ip link set $iface up"
  echo "  Restaurar IP y rutas desde backup o sistema"
  echo "  Verificar gateway"
  exit 0
fi

# EJECUCIÓN REAL
log "Simulando blackout de red en interfaz $iface durante $duration segundos"
send_mail "⚠️ El servidor $HOSTNAME inicia blackout de red\n\nInterfaz: $iface\nDuración: $duration segundos\nFecha y hora: $(date)"
log "Esperando 60 segundos para garantizar entrega del correo..."
sleep 60

backup_network_state
ip link set "$iface" down || { log "ERROR al bajar interfaz $iface"; exit 1; }

log "Interfaz $iface desactivada. Esperando $duration segundos..."
sleep "$duration"

log "Reactivando interfaz $iface"
ip link set "$iface" up || { log "ERROR al subir interfaz $iface"; exit 1; }
sleep 2
restore_network_state

send_mail "✅ Blackout finalizado correctamente en $HOSTNAME\n\nInterfaz: $iface\nFecha y hora: $(date)"
log "Proceso completado satisfactoriamente."
exit 0
