# Privacy Notes

- Weather uses device location when permission is granted.
- External IP lookups use FreeIPAPI.
- External IP location display is enabled by default for new installs and can be disabled in Settings.
- Travel advisory uses Smartraveller and is enabled by default.
- Weather alerts use WeatherKit and stay off until you enable them.
- Regional security uses ReliefWeb and stays off until you enable it.
- Advisory and regional security scope use the current country plus bordering countries when country context is available.
- External lookups are cached to reduce noise, latency, and battery impact.
- Anonymous TelemetryDeck analytics are enabled by default.
- `app_install_first_seen`, `app_launch`, and `app_background_active_day` are always sent to estimate install, launch, and background reach.
- `app_active_day`, `primary_ui_opened`, and `settings_opened` follow the in-app `Share anonymous analytics` setting.
- Analytics payloads include only app name, version, build number, distribution channel, and app type.
- Analytics do not include usernames, emails, locations, IP addresses, file names, or document titles.
- Release and update infrastructure should avoid embedding secrets in the repo.
