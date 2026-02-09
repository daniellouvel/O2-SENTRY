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

#### 1.1 Try/catch dans _discoverServices() — FAIT
`_discoverServices()` est maintenant encadre d'un try/catch. En cas d'echec
de `discoverServices()` ou `setNotifyValue()`, l'etat passe en `disconnected`
et `_scheduleReconnect()` est appele.
```
Fichier : bluetooth_service.dart, methode _discoverServices()
```

#### 1.2 Timeout sur la connexion BLE — FAIT
Ajout d'un timeout de 10 secondes sur `d.connect()` pour eviter les blocages
indefinis sur certains appareils Android.
```
Fichier : bluetooth_service.dart, methode _connectToDevice()
-> await d.connect(timeout: const Duration(seconds: 10))
```

#### 1.3 Watchdog sur le flux mV — FAIT
Timer `_mvWatchdog` reset a chaque reception mV via `_resetMvWatchdog()`.
Si aucune donnee pendant 10 secondes et etat = connected, force deconnexion
+ reconnexion automatique. Cancel dans `dispose()` et `forgetDevice()`.
```
Fichier : bluetooth_service.dart
Nouveau champ : Timer? _mvWatchdog
Nouvelle methode : _resetMvWatchdog()
```

#### 1.4 Gestion de la reprise d'app (lifecycle) — FAIT
`_HomeScreenState` implemente `WidgetsBindingObserver`. Sur `AppLifecycleState.resumed`,
appel de `btService.startScan()` (la garde `if connected return` empeche un scan inutile).
```
Fichier : home_screen.dart
```

---

### AXE 2 - SECURITE PLONGEE (Priorite HAUTE)

#### 2.1 Alarme sonore/vibration — FAIT
Vibration haptique (`HapticFeedback.heavyImpact()`) declenchee sur :
- Tension sonde anormale (hors plage du modele)
- Sonde perimee (> 12 mois)
- FO2 > 40% (melange hyperoxique) — nouvelle banniere orange
Anti-spam : cooldown de 3 secondes entre vibrations (`_lastVibration`).
```
Fichier : home_screen.dart
Import : flutter/services.dart
Nouvelles bannieres : FO2 > 40% (orange), sonde perimee (rouge)
```

#### 2.2 Plage d'alarme mV configurable par modele de sonde — FAIT
Le modele de sonde est maintenant persiste dans SharedPreferences avec ses
plages mV (min/max). Les alarmes utilisent les seuils dynamiques du modele
au lieu des valeurs fixes 7.0/14.0.
```
Fichier : bluetooth_service.dart
Nouveaux champs : sensorModel, sensorMvMin, sensorMvMax
Nouvelle methode : saveSensorModel(name, min, max)
Persistence : sensor_model, sensor_mv_min, sensor_mv_max dans SharedPreferences

Fichier : config_page.dart
initState : charge le modele sauvegarde depuis btService.sensorModel
onChanged : appelle btService.saveSensorModel() avec les specs du modele
Cas "Custom (Manuel)" : garde les plages precedentes

Fichier : home_screen.dart
mvAlarm : utilise btService.sensorMvMin / sensorMvMax
```

#### 2.3 Verification de calibration — FAIT
Avant calibration, verification que la tension mV est dans la plage
raisonnable [5.0, 16.0]. Hors plage : dialog d'erreur, calibration refusee.
```
Fichier : config_page.dart, bouton CALIBRER
Nouvelle methode : _showError(title, msg) — dialog d'erreur
```

#### 2.4 Stabilite de la mesure avant calibration — FAIT
Buffer circulaire de 10 mesures mV dans bluetooth_service.dart. Avant
calibration, verification : >= 10 mesures requises + ecart-type <= 0.15 mV.
```
Fichier : bluetooth_service.dart
Nouveau champ : _mvBuffer (List<double>, max 10)
Getter : recentMv (List.unmodifiable)
Alimentation : dans onValueReceived du listener BLE

Fichier : config_page.dart
Import : dart:math (pow, sqrt)
Nouvelle methode : _stdDev(values) — calcul ecart-type
Verification : buffer.length < 10 => refus, stdDev > 0.15 => refus
```

---

### AXE 3 - QUALITE DU CODE (Priorite MOYENNE)

#### 3.1 sensor_model.dart n'est pas utilise — FAIT
Fichier `lib/models/sensor_model.dart` supprime (+ repertoire `lib/models/` vide).
config_page.dart utilise ses propres specs localement.

#### 3.2 Version en dur dans home_screen.dart — FAIT
Version lue dynamiquement via `package_info_plus` (`PackageInfo.fromPlatform()`).
Dependance ajoutee dans pubspec.yaml. Version pubspec corrigee a `1.4.0+1`.
```
Fichiers : pubspec.yaml, home_screen.dart
```

#### 3.3 Pas de gestion d'erreur sur SharedPreferences — FAIT
Try/catch ajoute sur tous les appels SharedPreferences dans bluetooth_service.dart :
`init()`, `saveCalibration()`, `savePPO2()`, `saveInstallDate()`, `forgetDevice()`,
`_connectToDevice()`. Valeurs par defaut conservees en cas d'echec.

#### 3.4 _discoverServices non awaite — FAIT
`_discoverServices()` conserve l'appel non-awaite (fire-and-forget) depuis
`_connectToDevice()` pour ne pas bloquer le listener connectionState,
mais possede maintenant son propre try/catch qui passe en `disconnected`
+ `_scheduleReconnect()` en cas d'erreur.
```
Fichier : bluetooth_service.dart
```

---

### AXE 4 - EXPERIENCE UTILISATEUR (Priorite MOYENNE)

#### 4.1 Bouton de reconnexion manuelle — FAIT
La banniere "SONDE DECONNECTEE" est maintenant cliquable (GestureDetector).
Appelle `btService.startScan()` avec debounce de 5 secondes (`_lastReconnectTap`).
Icone refresh + texte "APPUYEZ POUR RECONNECTER" pour guider l'utilisateur.
```
Fichier : home_screen.dart
Nouveau champ : DateTime? _lastReconnectTap
Nouvelle methode : _manualReconnect()
Case disconnected : wrappee dans GestureDetector
```

#### 4.2 Affichage de la tension mV sur l'ecran principal — FAIT
La tension mV est affichee sous la valeur FO2% dans la jauge circulaire.
Texte discret (13px, Colors.white38) pour ne pas distraire du FO2.
```
Fichier : home_screen.dart
Ajout dans la Column interne du Stack (jauge) : "XX.XX mV"
```

#### 4.3 Historique / Tendance FO2 — FAIT
Mini sparkline (50px) entre la jauge et le bloc MOD, affichant les 60
dernieres valeurs FO2. Courbe cyan semi-transparente, sans axes ni labels.
Dependance : fl_chart ^0.69.0 ajoutee dans pubspec.yaml.
```
Fichier : pubspec.yaml — fl_chart: ^0.69.0
Fichier : home_screen.dart
Nouveaux champs : _fo2History (List<double>, max 60), _maxHistory = 60
Nouvelle methode : _buildFO2Sparkline() — LineChart minimal
Alimentation : dans le StreamBuilder, si snapshot.hasData
```

#### 4.4 Indicateur de calibration — FAIT
Date de derniere calibration sauvegardee automatiquement dans
`saveCalibration()`. Banniere ambre "CALIBRATION REQUISE (> 24H)"
sur l'ecran principal si calibrationDate == null ou > 24h.
Informative seulement (pas de vibration).
```
Fichier : bluetooth_service.dart
Nouveau champ : DateTime? calibrationDate
Persistence : 'calibration_date' dans SharedPreferences (init + saveCalibration)

Fichier : home_screen.dart
Nouveau bool : calAlarm (null ou > 24h)
Banniere ambre apres les bannieres d'alarme rouge/orange
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

#### 6.2 Tests unitaires O2MathEngine — FAIT
12 tests unitaires couvrant calculateFO2 et calculateMOD :
- FO2 : air standard, double mV, zero mV, calMv=0 (garde), EAN32, sonde faible
- MOD : air ppO2=1.4, EAN32, EAN36, O2 pur, fo2=0 (garde), fo2 negatif (garde)
```
Fichier : test/services/o2_math_engine_test.dart (NOUVEAU)
12/12 tests passent
```

---

## RESUME PAR PRIORITE

| Priorite | Axe | Items |
|----------|-----|-------|
| Priorite | Axe | Items | Statut |
|----------|-----|-------|--------|
| HAUTE    | Fiabilite BLE | 1.1, 1.2, 1.3, 1.4 | TOUT FAIT |
| HAUTE    | Securite plongee | 2.1, 2.2, 2.3, 2.4 | TOUT FAIT |
| MOYENNE  | Qualite code | 3.1, 3.2, 3.3, 3.4 | TOUT FAIT |
| MOYENNE  | UX | 4.1, 4.2, 4.3, 4.4 | TOUT FAIT |
| BASSE    | ESP32 | 5.1, 5.2 | A FAIRE |
| BASSE    | Structure | 6.1, 6.2 | 6.2 FAIT, 6.1 A FAIRE |
