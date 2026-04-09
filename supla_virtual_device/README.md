# SUPLA Virtual Device

Ten addon uruchamia aktualny projekt [`BBart19/virtual-supla`](https://github.com/BBart19/virtual-supla) jako dodatek Home Assistant.

## Co jest nowe

- addon buduje nowy `virtual-supla`, a nie stary historyczny fork
- pelne `supla-virtual-device.cfg` wpisujesz bezposrednio w zakladce **Konfiguracja**
- stan urzadzenia, `dev_guid` i `last_state.txt` sa trzymane trwale w `/data/var`
- mozesz dalej korzystac z plikow z Home Assistanta, np. przez sciezki w `/config/...`

## Konfiguracja

Najwazniejsze pole addonu to:

- `config` - pelna zawartosc pliku `supla-virtual-device.cfg`

Opcjonalnie:

- `debug` - uruchamia `supla-virtual-device -D`

Jesli uruchamiasz dwie instancje addonu na tym samym brokerze MQTT, ustaw rozne
`client_name` w sekcji `[MQTT]`. Ten sam MQTT client ID w dwoch instancjach
powoduje, ze broker rozlacza jedna z nich.

Domyslny config w `config.yaml` jest zapisany jako zwarty blok YAML `|-`, zeby byl czytelniejszy. Trzeba jednak uczciwie zaznaczyc, ze Home Assistant moze po edycji i zapisie przepisac ten wielolinijkowy string po swojemu. To zachowanie edytora HA, a nie samego addonu.

## MQTT watchdog

Jesli w konfiguracji jest sekcja `[MQTT]` z ustawionym `host`, addon pilnuje dostepnosci brokera MQTT:

- nie startuje `supla-virtual-device`, dopoki broker MQTT nie odpowiada
- zatrzymuje `supla-virtual-device`, gdy broker MQTT przestaje odpowiadac
- uruchamia go ponownie dopiero po powrocie brokera

Dzieki temu SUPLA nie powinna mylaco pokazywac urzadzen jako online, gdy backend MQTT juz nie dziala.

Pelny wzor wszystkich opcji znajdziesz tutaj:

- https://github.com/BBart19/virtual-supla/blob/main/supla-virtual-device.cfg.sample

## Przyklad

```yaml
debug: false
config: |-
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

Jesli uzywasz kanalow plikowych, odwolywaj sie do sciezek dostepnych w kontenerze addonu, najczesciej:

- `/config/...`
- `/data/...`
