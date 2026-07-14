# Dahua VTO to MQTT

Dodatek uruchamia projekt [DahuaVTO2MQTT](https://gitlab.com/elad.bar/DahuaVTO2MQTT) w Home Assistant i publikuje zdarzenia z wideodomofonów VTO, kamer oraz rejestratorów Dahua do brokera MQTT.

Obsługiwane architektury:

- `amd64`
- `aarch64`

Szczegółowa konfiguracja i przykłady znajdują się w pliku [DOCS.md](DOCS.md).

## Najważniejsze funkcje

- konfiguracja bezpośrednio w panelu dodatku Home Assistant
- publikowanie surowych zdarzeń Dahua do MQTT
- komendy MQTT, między innymi otwieranie drzwi
- metryki Prometheus pod adresem `http://ADRES_HOME_ASSISTANT:9563/metrics`
- walidacja wymaganych danych przed uruchomieniem aplikacji

## Źródło

Dodatek korzysta z obrazu projektu `elad-bar/DahuaVTO2MQTT`, udostępnionego na licencji Apache-2.0. Obrazy bazowe są przypięte do sprawdzonych digestów dla obu obsługiwanych architektur, aby build był odtwarzalny.
