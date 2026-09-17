#!/bin/bash
set -euo pipefail

REPO="${1:-/root/raw-gadget}"
KVER="$(uname -r)"
MOD_DEST="/lib/modules/${KVER}/kernel/drivers/usb/gadget"

echo "==> Kernel en uso: ${KVER}"

if [ ! -d "/usr/src/linux-headers-${KVER}" ]; then
    echo "==> Instalando headers del kernel"
    apt-get update
    apt-get install -y "pve-headers-${KVER}" gcc make
fi

if [ ! -d "${REPO}/dummy_hcd" ]; then
    echo "==> Clonando raw-gadget en ${REPO}"
    mkdir -p "$(dirname "${REPO}")"
    git clone https://github.com/xairy/raw-gadget.git "${REPO}"
fi

echo "==> Compilando dummy_hcd"
make -C "${REPO}/dummy_hcd"

echo "==> Instalando módulo en ${MOD_DEST}"
install -d "${MOD_DEST}"
install -m 644 "${REPO}/dummy_hcd/dummy_hcd.ko" "${MOD_DEST}/"
depmod -a

echo "==> Cargando dummy_hcd"
# undrive.conf's install line ends in "sleep", so modprobe's exit code is meaningless: check sysfs
modprobe dummy_hcd || true
ls /sys/class/udc/dummy_udc.* >/dev/null 2>&1 || {
    echo "FAIL: dummy_hcd no se pudo cargar."
    echo "Si el mensaje habla de 'Required key not available' o 'module verification failed',"
    echo "es el firmado de módulos de Proxmox: necesitas firmar dummy_hcd.ko o"
    echo "arrancar con module.sig_enforce=0."
    exit 1
}

echo "==> Cargando g_mass_storage"
modprobe -r g_mass_storage 2>/dev/null || true
modprobe g_mass_storage
sleep 1
grep -q configured /sys/class/udc/dummy_udc.*/state 2>/dev/null || lsusb | grep -qi UndriveVirtualUSB || {
    echo "FAIL: g_mass_storage no se enganchó al UDC. Revisa 'dmesg | tail -30' (error -2 = no encuentra la imagen)"
    exit 1
}

echo "==> Verificación"
lsmod | grep -E "dummy|g_mass_storage" || true
echo "Done!"
