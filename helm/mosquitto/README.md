# Mosquitto

Broker MQTT du namespace `home-assistant` (clients : Zigbee2MQTT, Home Assistant).

- Service : `mosquitto.home-assistant.svc.cluster.local:1883`
- Auth obligatoire (`allow_anonymous false`), utilisateurs `zigbee2mqtt` et `homeassistant`.

## Régénérer les mots de passe

```bash
touch passwd && chmod 600 passwd
docker run --rm -v "$PWD:/w" --entrypoint sh eclipse-mosquitto:2.0.22 -c \
  "mosquitto_passwd -b /w/passwd zigbee2mqtt '<mdp-z2m>' && mosquitto_passwd -b /w/passwd homeassistant '<mdp-ha>'"
kubectl create secret generic mosquitto-auth -n home-assistant --from-file=passwd=passwd --dry-run=client -o yaml \
  | kubeseal --controller-name=sealed-secrets --controller-namespace=sealed-secrets -o yaml
```

Reporter la valeur `passwd` dans `values.yaml` (`sealedSecret.encryptedData.passwd`). Ne jamais commiter `passwd`.
