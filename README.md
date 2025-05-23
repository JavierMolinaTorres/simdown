# simdown.sh

**Simula un apagón de red temporal en servidores Linux desconectando una interfaz de red.**

### 🛠 Funcionalidad
- Desactiva una interfaz de red durante un tiempo determinado.
- Guarda y restaura IP y rutas automáticamente.
- Envía aviso por correo si `mail` está disponible.
- Permite probar comportamiento de servicios ante fallos de red simulados.

### 📦 Requisitos
- Bash
- `ip`, `ping`, `mail` (mailutils recomendado)
- Permisos de root (requerido para desactivar interfaces)

### 🚀 Uso
```bash
sudo ./simdown.sh -i ens3 -t 120
```

### 🔧 Opciones
- `-i, --interface` — Interfaz de red a desconectar (ej. `eth0`, `ens3`)
- `-t, --time` — Tiempo en segundos de desconexión (por defecto 300)
- `--log archivo.log` — Ruta para el log
- `--email correo` — Enviar notificación a correo especificado
- `--no-email` — No enviar correos
- `--preview` — Solo muestra lo que haría

### 📧 Recomendación para correo
Instala `mailutils`:
```bash
sudo apt install mailutils
```

### 📜 Licencia
[MIT](LICENSE)
