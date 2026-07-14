# Dahua VTO to MQTT — dokumentacja

## Konfiguracja

Po instalacji otwórz zakładkę **Konfiguracja** dodatku i uzupełnij:

```yaml
dahua_vto_host: 192.168.1.20
dahua_vto_username: admin
dahua_vto_password: twoje-haslo-vto
mqtt_broker_host: core-mosquitto
mqtt_broker_port: 1883
mqtt_broker_username: mqtt-user
mqtt_broker_password: mqtt-password
mqtt_broker_topic_prefix: DahuaVTO
mqtt_broker_client_id: DahuaVTO2MQTT
debug: false
```

`dahua_vto_host` musi być samym adresem IP lub nazwą hosta, bez `http://`, `https://` i bez numeru portu. Aplikacja łączy się ze strumieniem zdarzeń Dahua na stałym porcie TCP `5000`.

Jeżeli korzystasz z oficjalnego dodatku Mosquitto broker, jego domyślna nazwa hosta to `core-mosquitto`. Dla zewnętrznego brokera wpisz jego adres IP lub nazwę DNS.

Każda uruchomiona instancja klienta MQTT musi mieć unikalne `mqtt_broker_client_id`. Powielony identyfikator powoduje wzajemne rozłączanie klientów przez broker.

Prefiks `mqtt_broker_topic_prefix` podawaj bez końcowego ukośnika.

## Tematy MQTT

Zdarzenia są publikowane jako surowe wiadomości MQTT pod wybranym prefiksem. Projekt upstream nie wysyła komunikatów MQTT Discovery, więc encje nie pojawią się automatycznie w Home Assistant.

Przykładowy temat zdarzenia:

```text
DahuaVTO/CallNoAnswered/Event
```

Otwieranie pierwszych drzwi:

```text
temat: DahuaVTO/Command/Open
payload: pusty
```

Wybór drzwi w urządzeniu obsługującym więcej niż jedno wyjście:

```text
temat: DahuaVTO/Command/Open
payload: {"Door": 2}
```

Pełna lista zdarzeń i komend znajduje się w [dokumentacji upstream](https://gitlab.com/elad.bar/DahuaVTO2MQTT/-/blob/master/MQTTEvents.MD).

## Metryki Prometheus

Exporter działa wewnątrz kontenera na porcie `9563`:

```text
http://ADRES_HOME_ASSISTANT:9563/metrics
```

Port hosta można zmienić lub wyłączyć w zakładce **Sieć** dodatku. Sam endpoint nie wymaga uwierzytelnienia, dlatego nie wystawiaj go bezpośrednio do Internetu.

Watchdog sprawdza dostępność endpointu `/metrics`. Potwierdza to działanie procesu i eksportera, ale nie gwarantuje aktywnego połączenia z VTO ani brokerem MQTT; ich stan jest widoczny w logach i metrykach.

## Diagnostyka

Opcja `debug: true` włącza szczegółowe logi upstream. Mogą one zawierać surowe zdarzenia i dane urządzenia, dlatego przejrzyj je przed publicznym udostępnieniem.

Jeżeli dodatek nie łączy się z urządzeniem, sprawdź kolejno:

1. Czy Home Assistant ma dostęp sieciowy do VTO na TCP `5000`.
2. Czy adres VTO nie zawiera protokołu ani portu.
3. Czy dane logowania do VTO są poprawne.
4. Czy broker MQTT jest osiągalny na skonfigurowanym porcie.
5. Czy identyfikator klienta MQTT nie jest używany przez inny proces.

Upstream nie obsługuje TLS dla połączenia z brokerem MQTT.
