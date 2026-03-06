# Privacy Notes

- Weather uses device location when permission is granted.
- External IP lookups use FreeIPAPI.
- External IP location display is enabled by default for new installs and can be disabled in Settings.
- Travel advisory uses Smartraveller and is enabled by default.
- Weather alerts use WeatherKit and stay off until you enable them.
- Regional security uses ReliefWeb and stays off until you enable it.
- Advisory and regional security scope use the current country plus bordering countries when country context is available.
- External lookups are cached to reduce noise, latency, and battery impact.
- No third-party analytics or telemetry are planned for v1.
- Release and update infrastructure should avoid embedding secrets in the repo.
