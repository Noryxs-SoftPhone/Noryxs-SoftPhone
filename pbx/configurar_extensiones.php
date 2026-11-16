<?php
/*
 * NORYXS — crea/actualiza las extensiones de prueba en FreePBX 17.
 * Uso en la centralita:  php /root/configurar_extensiones.php /root/noryxs-cred.txt
 * Formato del fichero: "ext | nombre | secreto | pin" (líneas con # se ignoran).
 * Las contraseñas no se imprimen.
 */
$bootstrap_settings['freepbx_auth'] = false;
include '/etc/freepbx.conf';
$fp = FreePBX::Create();
$db = $fp->Database;

$file = $argv[1] ?? '/root/noryxs-cred.txt';
foreach (file($file) as $line) {
    $line = trim($line);
    if ($line === '' || $line[0] === '#') continue;
    [$ext, $name, $secret, $pin] = array_map('trim', explode('|', $line));

    if (!$fp->Core->getUser($ext)) {
        // Igual que "Quick Create Extension" del panel: dispositivo + usuario + buzón
        $fp->Core->processQuickCreate('pjsip', $ext, [
            'name' => $name,
            'outboundcid' => '',
            'email' => '',
            'vm' => 'yes',
            'vmpwd' => $pin,
        ]);
        echo "creada  $ext ($name)\n";
    } else {
        echo "existe  $ext ($name)\n";
    }

    // Secreto conocido y varios contactos (NORYXS + teléfono físico)
    $set = function ($kw, $val) use ($db, $ext) {
        $db->prepare("DELETE FROM sip WHERE id = ? AND keyword = ?")->execute([$ext, $kw]);
        $db->prepare("INSERT INTO sip (id, keyword, data, flags) VALUES (?, ?, ?, 0)")->execute([$ext, $kw, $val]);
    };
    $set('secret', $secret);
    $set('max_contacts', '3');
    $set('remove_existing', 'yes');
    $set('qualifyfreq', '60');
    $set('media_encryption', 'no');      // SRTP opcional más adelante
    $set('allowsubscribe', 'yes');       // BLF / dialog-info
    $set('allow', 'g722&ulaw&alaw&opus');
}
echo "ok\n";
