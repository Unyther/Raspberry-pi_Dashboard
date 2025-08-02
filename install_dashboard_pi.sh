#!/bin/bash

set -e

PROJECT_DIR="/var/www/html/dashboard"

# --- Installer les paquets nécessaires ---
echo "[1/7] Installation des paquets nécessaires..."
sudo apt update
sudo apt install -y apache2 php php-cli php-curl git curl unzip

# Installer Websocat pour terminal SSH
if ! command -v websocat &> /dev/null; then
  echo "Installation de Websocat..."
  sudo curl -sLo /usr/local/bin/websocat https://github.com/vi/websocat/releases/latest/download/websocat_amd64-linux
  sudo chmod +x /usr/local/bin/websocat
fi

# --- Créer structure de fichiers ---
echo "[2/7] Création de la structure du projet..."
sudo mkdir -p "$PROJECT_DIR/backend/api"
sudo mkdir -p "$PROJECT_DIR/frontend/assets/css"
sudo mkdir -p "$PROJECT_DIR/frontend/assets/js"
sudo mkdir -p "$PROJECT_DIR/config"

# --- Fichiers backend ---
echo "[3/7] Ajout des fichiers backend..."
cat <<'EOF' | sudo tee $PROJECT_DIR/backend/api/stats.php > /dev/null
<?php
header('Content-Type: application/json');
echo json_encode([
  'cpu_temp' => exec("cat /sys/class/thermal/thermal_zone0/temp") / 1000,
  'cpu_usage' => sys_getloadavg()[0],
  'ram_total' => intval(shell_exec("free -m | awk '/Mem:/ { print \$2 }")),
  'ram_used' => intval(shell_exec("free -m | awk '/Mem:/ { print \$3 }")),
  'uptime' => shell_exec("uptime -p"),
  'hostname' => gethostname(),
  'ip' => getHostByName(getHostName()),
  'processes' => shell_exec("ps aux | wc -l")
]);
EOF

cat <<'EOF' | sudo tee $PROJECT_DIR/backend/api/login.php > /dev/null
<?php
session_start();
$password_hash = '5f4dcc3b5aa765d61d8327deb882cf99'; // = "password"
if ($_POST['password'] && md5($_POST['password']) === $password_hash) {
  $_SESSION['auth'] = true;
  header('Location: /dashboard/frontend/dashboard.html');
  exit;
} else {
  echo "Mauvais mot de passe.";
}
EOF

cat <<'EOF' | sudo tee $PROJECT_DIR/backend/api/ssh.php > /dev/null
<?php
session_start();
if (!isset($_SESSION['auth'])) {
  http_response_code(403);
  exit;
}
$cmd = $_POST['cmd'] ?? '';
$danger = ['rm', 'shutdown', 'reboot', 'mkfs', ':(){', '>', '<'];
foreach ($danger as $bad) {
  if (stripos($cmd, $bad) !== false) {
    echo "Commande dangereuse bloquée.";
    exit;
  }
}
echo shell_exec($cmd);
EOF

# --- Fichiers frontend ---
echo "[4/7] Ajout des fichiers frontend..."
cat <<'EOF' | sudo tee $PROJECT_DIR/frontend/index.html > /dev/null
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Connexion</title>
  <link rel="stylesheet" href="assets/css/style.css">
</head>
<body>
  <form method="POST" action="../backend/api/login.php">
    <h2>Connexion</h2>
    <input type="password" name="password" placeholder="Mot de passe" required>
    <button type="submit">Connexion</button>
  </form>
</body>
</html>
EOF

cat <<'EOF' | sudo tee $PROJECT_DIR/frontend/dashboard.html > /dev/null
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Dashboard Pi</title>
  <link rel="stylesheet" href="assets/css/style.css">
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
  <h1>Dashboard Raspberry Pi</h1>
  <div id="stats"></div>
  <canvas id="ramChart"></canvas>
  <textarea id="cmd" placeholder="Commande"></textarea>
  <button onclick="sendCommand()">Exécuter</button>
  <pre id="output"></pre>
  <script src="assets/js/dashboard.js"></script>
</body>
</html>
EOF

cat <<'EOF' | sudo tee $PROJECT_DIR/frontend/assets/css/style.css > /dev/null
body {
  font-family: sans-serif;
  background: #121212;
  color: #eee;
  padding: 20px;
}
input, button, textarea {
  margin: 5px;
  padding: 10px;
  font-size: 1em;
}
pre {
  background: #222;
  padding: 10px;
  overflow-x: auto;
}
EOF

cat <<'EOF' | sudo tee $PROJECT_DIR/frontend/assets/js/dashboard.js > /dev/null
async function fetchStats() {
  const res = await fetch('../backend/api/stats.php');
  const data = await res.json();
  document.getElementById('stats').innerHTML = `
    Temp CPU : ${data.cpu_temp} °C<br>
    CPU Load : ${data.cpu_usage}<br>
    RAM utilisée : ${data.ram_used} Mo / ${data.ram_total} Mo<br>
    Uptime : ${data.uptime}<br>
    IP : ${data.ip}<br>
    Processus : ${data.processes}
  `;

  new Chart(document.getElementById('ramChart'), {
    type: 'doughnut',
    data: {
      labels: ['Utilisée', 'Libre'],
      datasets: [{
        data: [data.ram_used, data.ram_total - data.ram_used],
        backgroundColor: ['#ff6384', '#36a2eb']
      }]
    }
  });
}

async function sendCommand() {
  const cmd = document.getElementById('cmd').value;
  const res = await fetch('../backend/api/ssh.php', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `cmd=${encodeURIComponent(cmd)}`
  });
  const output = await res.text();
  document.getElementById('output').innerText = output;
}

fetchStats();
setInterval(fetchStats, 5000);
EOF

# --- Droits ---
echo "[5/7] Configuration des permissions..."
sudo chown -R www-data:www-data $PROJECT_DIR
sudo chmod -R 755 $PROJECT_DIR

# --- Activation Apache ---
echo "[6/7] Activation Apache..."
sudo systemctl enable apache2
sudo systemctl restart apache2

# --- Fini ---
echo "[7/7] Terminé !"
echo "➡️ Accède à ton dashboard ici : http://$(hostname -I | awk '{print $1}')/dashboard/frontend"
echo "🔐 Mot de passe par défaut : password"
echo "🛠 Pour changer le mot de passe : modifie login.php (hash MD5 à changer)"
