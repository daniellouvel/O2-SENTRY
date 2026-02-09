# O2-Sentry - Modifications & Axes d'Amelioration
# Date : 09/02/2026

---

## PARTIE 1 : CORRECTIONS APPLIQUEES (Bug "Sonde Deconnectee")

### Probleme
La banniere "SONDE DECONNECTEE" s'affichait alors que les valeurs mV
evoluaient normalement (la sonde etait bien connectee).

### Cause racine
Le stack BLE Android envoyait un faux evenement `disconnected` pendant
la phase de connexion initiale. Cela declenchait un timer de reconnexion
(3 secondes). Apres ce delai, un scan BLE inutile demarrait. Comme l'ESP32
etait deja connecte, il ne s'annoncait plus en BLE. Le scan expirait
apres 15 secondes et passait l'etat a "disconnected" - sans toucher a la
souscription mV qui continuait de recevoir les donnees normalement.

### Corrections (bluetooth_service.dart)

#### 1. Garde dans startScan() (ligne 106)
AVANT :
```dart
void startScan() async {
    if (_isConnecting) return;
    if (_disposed) return;
    _setState(SentryConnectionState.scanning);
```
APRES :
```dart
void startScan() async {
    if (_isConnecting) return;
    if (_disposed) return;
    if (_currentState == SentryConnectionState.connected) return;  // AJOUT
    _setState(SentryConnectionState.scanning);
```
> Empeche de lancer un scan quand la sonde est deja connectee.

#### 2. Filtre sur le listener connectionState (lignes 161-173)
AVANT :
```dart
_deviceStateSubscription = d.connectionState.listen((state) {
    if (state == BluetoothConnectionState.disconnected) {
        _setState(SentryConnectionState.disconnected);
        _charSubscription?.cancel();
        _charSubscription = null;
        _isConnecting = false;
        _scheduleReconnect();
    } else if (state == BluetoothConnectionState.connected) {
        _setState(SentryConnectionState.connected);
    }
});
```
APRES :
```dart
_deviceStateSubscription = d.connectionState.listen((state) {
    if (state == BluetoothConnectionState.disconnected) {
        // Ne reagir que si on etait connecte (evite les faux evenements
        // pendant la phase de connexion/decouverte de services)
        if (_currentState == SentryConnectionState.connected) {
            _setState(SentryConnectionState.disconnected);
            _charSubscription?.cancel();
            _charSubscription = null;
            _isConnecting = false;
            _scheduleReconnect();
        }
    }
});
```
> Ignore les faux evenements "disconnected" du BLE Android pendant la phase
> de connexion initiale. Ne reagit qu'aux vraies deconnexions (quand on
> etait deja en etat "connected").

#### 3. Garde dans _scheduleReconnect() (lignes 225-230)
AVANT :
```dart
_reconnectTimer = Timer(const Duration(seconds: 3), () {
    if (!_disposed && _savedMac != null) {
        startScan();
    }
});
```
APRES :
```dart
_reconnectTimer = Timer(const Duration(seconds: 3), () {
    if (!_disposed &&
        _savedMac != null &&
        _currentState != SentryConnectionState.connected) {  // AJOUT
        startScan();
    }
});
```
> Si la connexion s'est retablie pendant les 3 secondes d'attente,
> on ne relance pas de scan inutile.

---

## PARTIE 2 : AXES D'AMELIORATION

---

### AXE 1 - FIABILITE BLE (Priorite HAUTE)

#### 1.1 Try/catch dans _discoverServices()
Actuellement, `_discoverServices()` n'a aucun try/catch. Si `discoverServices()`
ou `setNotifyValue()` echoue, l'etat reste bloque sur "connecting" indefiniment.
```
Fichier : bluetooth_service.dart, methode _discoverServices()
Action : Encadrer avec try/catch, passer en disconnected + scheduleReconnect en cas d'erreur
```

#### 1.2 Timeout sur la connexion BLE
`d.connect()` peut rester bloque indefiniment sur certains appareils Android.
```
Fichier : bluetooth_service.dart, methode _connectToDevice()
Action : Ajouter un timeout -> await d.connect(timeout: Duration(seconds: 10))
```

#### 1.3 Watchdog sur le flux mV
Si aucune donnee mV n'est recue pendant X secondes alors que l'etat est
"connected", la connexion est probablement morte sans evenement BLE.
```
Fichier : bluetooth_service.dart
Action : Timer reset a chaque reception mV. Si expire -> forcer reconnexion.
Duree suggeree : 10-15 secondes sans donnee = deconnexion
```

#### 1.4 Gestion de la reprise d'app (lifecycle)
Quand l'app revient du background, la connexion BLE peut etre perdue
silencieusement (Android tue les connexions BLE en arriere-plan).
```
Fichier : home_screen.dart
Action : Ajouter WidgetsBindingObserver, sur didChangeAppLifecycleState
         -> verifier connexion et relancer scan si necessaire
```

---

### AXE 2 - SECURITE PLONGEE (Priorite HAUTE)

#### 2.1 Alarme sonore/vibration
Les alarmes visuelles (banniere rouge) ne suffisent pas en situation de
preparation de plongee (bruit, stress, attention ailleurs).
```
Action : Ajouter vibration (HapticFeedback ou vibration package) +
         son d'alerte pour :
         - Tension sonde anormale (< 7 mV ou > 14 mV)
         - Sonde perimee (> 12 mois)
         - FO2 > 40% (melange hyperoxique)
```

#### 2.2 Plage d'alarme mV configurable par modele de sonde
Actuellement les seuils 7.0 et 14.0 mV sont en dur dans home_screen.dart.
Le modele de sonde est selectionne dans config_page mais n'est pas sauvegarde
et ses plages (sensorSpecs) ne sont pas utilisees pour les alarmes.
```
Fichier : config_page.dart (sensorSpecs) + home_screen.dart (mvAlarm)
Action : Sauvegarder le modele selectionne + utiliser ses plages min/max
         pour l'alarme au lieu des valeurs fixes 7.0/14.0
```

#### 2.3 Verification de calibration
Aucun controle n'empeche de calibrer avec une valeur mV aberrante
(ex: 0.5 mV ou 25 mV). Une mauvaise calibration fausse tous les calculs.
```
Fichier : config_page.dart, bouton CALIBRER
Action : Refuser calibration si mV hors plage raisonnable (ex: < 5.0 ou > 16.0)
         avec message d'avertissement
```

#### 2.4 Stabilite de la mesure avant calibration
La calibration prend la valeur mV instantanee. Si la sonde n'est pas
stabilisee, la reference sera fausse.
```
Action : Verifier que la variance des 10 dernieres mesures est < seuil
         avant d'autoriser la calibration. Sinon, afficher "Attendre
         stabilisation..."
```

---

### AXE 3 - QUALITE DU CODE (Priorite MOYENNE)

#### 3.1 sensor_model.dart n'est pas utilise
Le fichier `lib/models/sensor_model.dart` definit SensorProfile et sensorLibrary
mais n'est importe nulle part. config_page.dart redefinit ses propres specs
dans un Map local.
```
Action : Utiliser sensor_model.dart comme source unique pour les modeles
         de sondes, ou le supprimer
```

#### 3.2 Version en dur dans home_screen.dart
La version "1.4.0" est ecrite en dur dans _HomeScreenState.
```
Fichier : home_screen.dart ligne 17
Action : Lire depuis pubspec.yaml via package_info_plus
```

#### 3.3 Pas de gestion d'erreur sur SharedPreferences
Les appels SharedPreferences dans init(), saveCalibration(), etc.
n'ont pas de try/catch. Si le stockage echoue, l'app crash silencieusement.
```
Action : Ajouter try/catch avec valeurs par defaut sur chaque acces
```

#### 3.4 _discoverServices non awaite
Dans _connectToDevice(), `_discoverServices(d)` est appele sans await.
C'est une methode async void (fire-and-forget). Si elle echoue, aucune
erreur n'est capturee par le try/catch de _connectToDevice.
```
Fichier : bluetooth_service.dart ligne 181
Action : Faire de _discoverServices une Future<void> et l'awaiter,
         ou ajouter son propre try/catch
```

---

### AXE 4 - EXPERIENCE UTILISATEUR (Priorite MOYENNE)

#### 4.1 Bouton de reconnexion manuelle
Si la sonde est deconnectee, l'utilisateur n'a aucun moyen de forcer
une tentative de reconnexion (il doit attendre le cycle automatique).
```
Fichier : home_screen.dart, banniere SONDE DECONNECTEE
Action : Rendre la banniere cliquable -> appel btService.startScan()
         (avec un debounce pour eviter le spam)
```

#### 4.2 Affichage de la tension mV sur l'ecran principal
La tension mV n'est visible que dans la page configuration. Pour un
plongeur experimenté, cette info est utile pour evaluer l'etat de la sonde.
```
Fichier : home_screen.dart
Action : Ajouter un petit texte sous la jauge O2 : "10.52 mV"
```

#### 4.3 Historique / Tendance
Pas de visualisation de l'evolution de la FO2 dans le temps.
```
Action : Ajouter un mini-graphique (sparkline) des 60 dernieres secondes
         sous la jauge. Package suggere : fl_chart
```

#### 4.4 Indicateur de calibration
Aucune indication sur l'ecran principal de quand la derniere calibration
a ete effectuee ou si elle est recente.
```
Action : Sauvegarder la date de derniere calibration + afficher un
         avertissement si > 24h depuis le dernier calibrage
```

---

### AXE 5 - ROBUSTESSE ESP32 (Priorite BASSE)

#### 5.1 Format de donnees BLE
L'ESP32 envoie la tension en texte brut (string). C'est simple mais
fragile (encodage, caracteres parasites, etc.).
```
Fichier ESP32 : O2_sentry.ino
Action : Envoyer en binaire (float 4 bytes) au lieu de texte.
         Cote Flutter : lire les 4 bytes et convertir en double.
```

#### 5.2 Intervalle d'envoi
Pas de controle sur la frequence d'envoi de l'ESP32. Si l'ESP32
envoie trop vite, l'app peut etre submergee.
```
Action : Configurer un intervalle fixe cote ESP32 (ex: 500ms)
         et/ou limiter cote Flutter (throttle sur le stream mV)
```

---

### AXE 6 - STRUCTURE PROJET (Priorite BASSE)

#### 6.1 Fichier Arduino manquant
`esp/O2_sentry/O2_sentry.ino` contient du code Dart (copie du service BT),
pas du code Arduino C++. Le vrai code ESP32 n'est pas dans le depot.
```
Action : Remplacer par le vrai code Arduino/ESP32
```

#### 6.2 Tests unitaires
Aucun test unitaire n'existe pour O2MathEngine, la logique BLE,
ou les calculs de securite.
```
Action prioritaire : Tester O2MathEngine (FO2, MOD) car c'est critique
         pour la securite des plongeurs
```

---

## RESUME PAR PRIORITE

| Priorite | Axe | Items |
|----------|-----|-------|
| HAUTE    | Fiabilite BLE | 1.1, 1.2, 1.3, 1.4 |
| HAUTE    | Securite plongee | 2.1, 2.2, 2.3, 2.4 |
| MOYENNE  | Qualite code | 3.1, 3.2, 3.3, 3.4 |
| MOYENNE  | UX | 4.1, 4.2, 4.3, 4.4 |
| BASSE    | ESP32 | 5.1, 5.2 |
| BASSE    | Structure | 6.1, 6.2 |
