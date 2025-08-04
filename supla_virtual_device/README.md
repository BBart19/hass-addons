# SUPLA Virtual Device dla Home Assistant

Addon Home Assistant umożliwiający uruchomienie SUPLA Virtual Device.

## Funkcje

✅ **MQTT Integration** - przekazywanie danych z czujników przez MQTT  
✅ **Multi-channel Support** - obsługa wielu kanałów pomiarowych  
✅ **Smart Caching** - szybkie uruchamianie po pierwszym buildzie  
✅ **Home Assistant Integration** - pełna integracja z HA

## Konfiguracja

### Wymagane ustawienia:
- **email** - Twój email zarejestrowany w SUPLA Cloud
- **server_host** - Adres serwera SUPLA

### Opcjonalne ustawienia:
- **mqtt_enabled** - Włącz jeśli używasz MQTT
- **channels** - Konfiguracja kanałów do przekazywania danych poprzez plik /homeassistant/supla-virtual-device/supla-virtual-device.cfg

### Przykład konfiguracji kanałów:

