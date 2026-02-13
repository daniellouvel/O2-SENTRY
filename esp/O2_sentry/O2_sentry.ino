#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>

// UUIDs du projet O2-Sentry
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

Preferences preferences;
BLECharacteristic *pCharacteristic;
bool deviceConnected = false;
String finalDeviceName;

// --- Paramètres de simulation ---
float baseMv = 10.50;       // Tension de base (air ambiant ~20.9% O2)
float noiseMv = 0.03;       // Amplitude du bruit (± mV)
int batteryLevel = 95;      // Niveau batterie initial (%)
unsigned long lastBatDrain = 0;
const unsigned long BAT_DRAIN_INTERVAL = 60000; // Perte 1% toutes les 60s

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println(">> Client connecté");
    }
    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        Serial.println(">> Client déconnecté - relance advertising");
        pServer->getAdvertising()->start();
    }
};

void printHelp() {
    Serial.println("=== O2-SENTRY Simulateur ===");
    Serial.println("Commandes série :");
    Serial.println("  mv XX.XX   -> change la tension de base (ex: mv 10.50)");
    Serial.println("  bat XX     -> change le niveau batterie (ex: bat 75)");
    Serial.println("  noise X.XX -> change l'amplitude du bruit (ex: noise 0.05)");
    Serial.println("  air        -> preset air (10.50 mV)");
    Serial.println("  nx32       -> preset Nitrox 32 (16.05 mV)");
    Serial.println("  nx36       -> preset Nitrox 36 (18.06 mV)");
    Serial.println("  o2         -> preset O2 pur (52.63 mV)");
    Serial.println("  low        -> preset sonde faible (5.00 mV - alarme)");
    Serial.println("  high       -> preset sonde haute (15.00 mV - alarme)");
    Serial.println("  reset      -> efface la config et redemarre l'ESP32");
    Serial.println("  help       -> affiche ce menu");
    Serial.println("============================");
}

void handleSerialCommand() {
    if (!Serial.available()) return;

    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    cmd.toLowerCase();

    if (cmd.startsWith("mv ")) {
        baseMv = cmd.substring(3).toFloat();
        Serial.println("Base mV -> " + String(baseMv, 2));
    } else if (cmd.startsWith("bat ")) {
        batteryLevel = constrain(cmd.substring(4).toInt(), 0, 100);
        Serial.println("Batterie -> " + String(batteryLevel) + "%");
    } else if (cmd.startsWith("noise ")) {
        noiseMv = cmd.substring(6).toFloat();
        Serial.println("Bruit -> ±" + String(noiseMv, 3) + " mV");
    } else if (cmd == "air") {
        baseMv = 10.50;
        Serial.println("Preset AIR (20.9%) -> 10.50 mV");
    } else if (cmd == "nx32") {
        baseMv = 16.05;
        Serial.println("Preset NITROX 32 -> 16.05 mV");
    } else if (cmd == "nx36") {
        baseMv = 18.06;
        Serial.println("Preset NITROX 36 -> 18.06 mV");
    } else if (cmd == "o2") {
        baseMv = 52.63;
        Serial.println("Preset O2 PUR (100%) -> 52.63 mV");
    } else if (cmd == "low") {
        baseMv = 5.00;
        Serial.println("Preset SONDE FAIBLE -> 5.00 mV (alarme)");
    } else if (cmd == "high") {
        baseMv = 15.00;
        Serial.println("Preset SONDE HAUTE -> 15.00 mV (alarme)");
    } else if (cmd == "reset") {
        Serial.println("Effacement de la configuration...");
        preferences.begin("device-info", false);
        preferences.clear();
        preferences.end();
        Serial.println("Config effacee. Redemarrage...");
        delay(1000);
        ESP.restart();
    } else if (cmd == "help") {
        printHelp();
    } else {
        Serial.println("Commande inconnue: " + cmd);
    }
}

void setup() {
    Serial.begin(115200);

    // 1. Gestion de l'ID unique permanent
    preferences.begin("device-info", false);
    String storedID = preferences.getString("probe_id", "");

    if (storedID == "") {
        // Premier démarrage : on crée un ID de 4 caractères hex au hasard
        randomSeed(analogRead(0) ^ (micros() * 17));
        long randomNum = random(0x1000, 0xFFFF);
        storedID = String(randomNum, HEX);
        storedID.toUpperCase();
        preferences.putString("probe_id", storedID);
    }

    finalDeviceName = "O2-SENTRY-" + storedID;
    preferences.end();

    // 2. Initialisation BLE
    BLEDevice::init(finalDeviceName.c_str());
    BLEServer *pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    BLEService *pService = pServer->createService(SERVICE_UUID);
    pCharacteristic = pService->createCharacteristic(
                        CHARACTERISTIC_UUID,
                        BLECharacteristic::PROPERTY_READ |
                        BLECharacteristic::PROPERTY_NOTIFY
                      );
    pCharacteristic->addDescriptor(new BLE2902());

    pService->start();
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->start();

    Serial.println("Sonde démarrée : " + finalDeviceName);
    printHelp();

    lastBatDrain = millis();
}

void loop() {
    // Traiter les commandes série
    handleSerialCommand();

    // Décharge batterie simulée
    if (millis() - lastBatDrain >= BAT_DRAIN_INTERVAL) {
        lastBatDrain = millis();
        if (batteryLevel > 0) batteryLevel--;
    }

    if (deviceConnected) {
        // Simulation : tension de base + bruit gaussien simplifié
        float noise = (random(-1000, 1001) / 1000.0) * noiseMv;
        float mv = baseMv + noise;
        if (mv < 0) mv = 0;

        // Format : "mV,batterie" (ex: "10.52,95")
        String payload = String(mv, 2) + "," + String(batteryLevel);

        pCharacteristic->setValue(payload.c_str());
        pCharacteristic->notify();

        //Serial.println("TX: " + payload);
        delay(1000);
    } else {
        delay(100);
    }
}
