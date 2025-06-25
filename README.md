# 🚀 User Copy Script für RedHat/AlmaLinux

Ein einfaches Bash-Script zum Kopieren von Benutzern zwischen RedHat/AlmaLinux Servern.

## 📋 Was macht das Script?

Das Script kopiert einen kompletten Benutzer von einem Quellserver zu einem oder mehreren Zielservern:

- ✅ **Benutzerinformationen** (UID, GID, Shell, GECOS)
- ✅ **Passwort-Hash** aus /etc/shadow  
- ✅ **Gruppenmitgliedschaften**
- ✅ **Komplettes Home-Verzeichnis**
- ✅ **SSH-Keys** mit korrekten Berechtigungen
- ✅ **ACLs** (Access Control Lists)
- ✅ **Dateiberechtigungen** und Ownership

## 🎯 Anwendungsfall

Perfekt für das Kopieren von Benutzern aus der **Testumgebung** in die **Produktionsumgebung**!

## 📦 Installation

**Keine Installation nötig!** Einfach das Script herunterladen und ausführbar machen:

```bash
chmod +x copy_user.sh
```

## 🔧 Verwendung

### Grundlegende Syntax
```bash
./copy_user.sh -u USERNAME -s SOURCE_SERVER -t TARGET_SERVERS [OPTIONEN]
```

### Parameter

#### Pflichtparameter:
- `-u USERNAME` - Benutzername der kopiert werden soll
- `-s SOURCE_SERVER` - Quellserver (IP oder Hostname, verwenden Sie `localhost` wenn Sie auf dem Quellserver sind)
- `-t TARGET_SERVERS` - Zielserver (kommagetrennt für mehrere Server)

#### Optionale Parameter:
- `-k SSH_KEY` - Pfad zum SSH Private Key (Standard: ~/.ssh/id_rsa)
- `-p PORT` - SSH Port (Standard: 22)
- `-d` - Dry-run Modus (zeigt nur an was gemacht würde)
- `-v` - Verbose Modus (detaillierte Ausgabe)
- `--no-acl` - ACLs nicht kopieren
- `-h` - Hilfe anzeigen

## 🚀 Beispiele

### Einfaches Beispiel
```bash
# Benutzer von localhost zu einem Server kopieren
./copy_user.sh -u testuser -s localhost -t prod-server.local
```

### Mehrere Zielserver
```bash
# Benutzer zu mehreren Servern kopieren
./copy_user.sh -u developer -s localhost -t "prod1.local,prod2.local,prod3.local"
```

### Dry-Run (empfohlen für ersten Test)
```bash
# Erst testen was passieren würde
./copy_user.sh -u testuser -s localhost -t prod-server.local -d
```

### Mit SSH Key und custom Port
```bash
./copy_user.sh -u admin -s localhost -t target.local -k ~/.ssh/custom_key -p 2222
```

### Verbose Mode für Debugging
```bash
./copy_user.sh -u developer -s localhost -t prod.local -v
```

### Ohne ACLs (falls Probleme)
```bash
./copy_user.sh -u webuser -s localhost -t "prod1,prod2" --no-acl
```

## 🔐 Authentifizierung

### Option 1: SSH Keys (Empfohlen)
```bash
# SSH Key generieren (falls noch nicht vorhanden)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa

# Key zu Zielservern kopieren
ssh-copy-id root@zielserver1
ssh-copy-id root@zielserver2
```

**Vorteil:** Keine Passwort-Eingabe nötig!

### Option 2: Passwort-Authentifizierung
Wenn keine SSH Keys vorhanden sind:
- Das Script warnt Sie vor, dass Sie mehrmals das Passwort eingeben müssen
- Geben Sie einfach jedes Mal das gleiche root-Passwort ein
- Das ist völlig normal und okay!

## ⚠️ Wichtige Hinweise

### Vor der ersten Verwendung:
1. **Immer zuerst mit `-d` (Dry-Run) testen!**
2. Backup wichtiger Daten erstellen
3. Prüfen Sie die Zielserver-Liste sorgfältig

### Was Sie beachten sollten:
- 🔒 Das Script kopiert Passwort-Hashes - stellen Sie sicher, dass dies gewünscht ist
- 🔑 Verwenden Sie SSH-Keys für bessere Sicherheit
- 📋 Bei UID-Konflikten wird das Script Sie warnen
- 🗂️ ACLs werden nur kopiert wenn `getfacl`/`setfacl` verfügbar sind

### Berechtigungen:
- Root-Zugriff auf alle beteiligten Server erforderlich
- Sudo-Berechtigung reicht aus

## 🐛 Fehlerbehebung

### SSH-Verbindungsprobleme
```bash
# Testen Sie die SSH-Verbindung manuell:
ssh root@zielserver

# Prüfen Sie Firewall-Einstellungen
# Prüfen Sie SSH-Konfiguration
```

### Permission-Fehler
```bash
# Stellen Sie sicher, dass Sie root/sudo-Zugriff haben:
sudo -l
```

### UID-Konflikte
```bash
# Prüfen Sie ob die UID bereits verwendet wird:
id 1001  # Beispiel-UID
```

### ACL-Probleme
```bash
# Prüfen Sie ob ACL-Tools installiert sind:
which getfacl setfacl

# Falls nicht installiert:
yum install acl
```

## 📊 Beispiel-Ausgabe

### Erfolgreiche Ausführung:
```
[INFO] Starting user copy operation
[INFO] Username: testuser
[INFO] Source: localhost  
[INFO] Target(s): prod-server1,prod-server2
[INFO] Getting user information for 'testuser' from localhost
[INFO] User info retrieved successfully
[INFO] Starting user copy: testuser from localhost to prod-server1
[INFO] Creating user 'testuser' on prod-server1
[INFO] User 'testuser' created successfully on prod-server1
[INFO] Copying home directory for 'testuser'
[INFO] Home directory copied successfully
[INFO] Copying SSH keys for 'testuser'
[INFO] SSH keys copied successfully
[INFO] Copying ACLs for /home/testuser
[INFO] ACLs copied successfully
[INFO] User 'testuser' successfully copied to prod-server1
[INFO] User copy operation completed
```

### Dry-Run Ausgabe:
```
[WARNING] DRY RUN MODE - No changes will be made
[INFO] Would create user with following parameters:
  Username: testuser
  UID: 1001
  GID: 1001
  Home: /home/testuser
  Shell: /bin/bash
[WARNING] DRY RUN: Would copy /home/testuser from localhost to prod-server1
[WARNING] DRY RUN: Would copy SSH keys from /home/testuser/.ssh
```

## 🔧 Anpassungen

Das Script ist modular aufgebaut und kann leicht angepasst werden:

- Ändern Sie die Farben in den ersten Zeilen
- Erweitern Sie die Funktionen nach Bedarf  
- Passen Sie SSH-Optionen an

## 📝 Lizenz

Frei verwendbar für alle Zwecke.

## 👤 Autor

**RGa** - 2025-06-25

---

## 🆘 Support

Bei Problemen oder Fragen:
1. Prüfen Sie die Fehlerbehebung oben
2. Führen Sie das Script mit `-v` (verbose) aus
3. Testen Sie mit `-d` (dry-run) erst

**Viel Erfolg beim Benutzer-Kopieren!** 🎉
