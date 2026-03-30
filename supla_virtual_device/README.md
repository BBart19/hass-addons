# SUPLA Virtual Device

Ten addon uruchamia aktualny projekt [`BBart19/virtual-supla`](https://github.com/BBart19/virtual-supla) jako dodatek Home Assistant.

## Co jest nowe

- addon buduje nowy `virtual-supla`, a nie stary historyczny fork
- całe `supla-virtual-device.cfg` wpisujesz bezpośrednio w zakładce **Konfiguracja**
- stan urządzenia, `dev_guid` i `last_state.txt` są trzymane trwale w `/data/var`
- możesz dalej korzystać z plików z Home Assistanta, np. przez ścieżki w `/config/...`

## Konfiguracja

Najważniejsze pole addonu to:

- `config` - pełna zawartość pliku `supla-virtual-device.cfg`

Opcjonalnie:

- `debug` - uruchamia `supla-virtual-device -D`

## MQTT watchdog

Jesli w konfiguracji jest sekcja `[MQTT]` z ustawionym `host`, addon pilnuje
dostepnosci brokera MQTT:

- nie startuje `supla-virtual-device`, dopoki broker MQTT nie odpowiada
- zatrzymuje `supla-virtual-device`, gdy broker MQTT przestaje odpowiadac
- uruchamia go ponownie dopiero po powrocie brokera

Dzieki temu SUPLA nie powinna mylaco pokazywac urzadzen jako online, gdy
backend MQTT juz nie dziala.

Domyślnie addon startuje z prostym szkieletem konfiguracji. Pełny wzór wszystkich opcji znajdziesz tutaj:

- https://github.com/BBart19/virtual-supla/blob/main/supla-virtual-device.cfg.sample

## Przykład

```ini
[GLOBAL]
device_name=SUPLA VIRTUAL DEVICE
device_guid_file=./var/dev_guid
state_file=./var/last_state.txt

[SERVER]
host=svrX.supla.org
protocol_version=23
tcp_port=2015
ssl_port=2016
ssl_enabled=1

[AUTH]
email=you@example.com

[MQTT]
host=192.168.1.100
port=1883
username=mqtt-user
password=mqtt-password
client_name=supla-virtual-device

[CHANNEL_0]
function=TEMPERATURE
state_topic=sensors/temperature/state
```

## Uwaga

Jeśli używasz kanałów plikowych, odwołuj się do ścieżek dostępnych w kontenerze addonu, najczęściej:

- `/config/...`
- `/data/...`
