# App Store listing

Everything App Store Connect asks for, in one place. Character counts are checked by `python3` before each release.

## App information

| Field | Value |
|---|---|
| Name | DeviceMonitor |
| Subtitle (≤ 30) | Who's on your Wi‑Fi, right now |
| Bundle ID | `Anton.DeviceMonitor` (changing it later means a new app record) |
| Primary category | Utilities |
| Secondary category | Productivity |
| Age rating | 4+ |
| Price | Free |
| Copyright | © 2026 Anton Smedberg |
| Support URL | https://github.com/antonsmedberg/DeviceMonitor/issues |
| Privacy policy URL | https://github.com/antonsmedberg/DeviceMonitor/blob/main/Docs/PrivacyPolicy.md |

## Promotional text (≤ 170)

See every device on your Wi‑Fi, know the moment something new joins, and fix what's risky. Private by design: no account, everything stays on your iPhone.

## Description

See every device on your Wi‑Fi, know when something new joins, and fix what's risky — without an account.

DeviceMonitor finds the routers, computers, phones, printers, speakers, cameras and smart-home gear on your network and keeps checking whether they answer. A device is only marked offline after several missed checks, so one dropped packet never becomes a false alarm.

WHAT YOU GET
• An Overview of your network: who is online, offline, new or a stranger, what needs attention, your router's latency over the last hour and the outages seen in the last 24 hours
• A device list with search, filters for strangers and favourites, and each device's latency and jitter
• Device pages with a latency chart for the last hour, 6 hours or 24 hours, outage history for 24 hours, 30 and 90 days, a five-probe ping, a port check with plain-language advice, Wake-on-LAN, and links to web, SSH and screen sharing
• Activity: arrivals, departures and outages, a devices-online chart you can scrub hour by hour, and a map of every address on your network
• A security score that explains itself, a one-tap Trust for devices you recognise, a map of your network and who was online in each hour
• On supported iPhones, plain-language explanations written on-device by Apple Intelligence
• Siri and Shortcuts: "Scan my network" and "How is my network?"
• Built for iOS 27 with Liquid Glass, Dynamic Type, VoiceOver, iPad and iPhone Duo

PRIVATE BY DESIGN
No account, no ads, no analytics, no location. Everything is stored on your iPhone. The only permission is Local Network access, used to talk to the devices on your Wi‑Fi.

WHAT AN iPHONE APP CANNOT DO
iOS does not let apps keep scanning in the background, read MAC addresses, or send broadcast traffic, so DeviceMonitor watches your network while it is open and says clearly when something is not possible.

## Keywords (≤ 100)

network,scanner,wifi,lan,ping,devices,router,monitor,security,ports,bonjour,ip

## App Privacy ("nutrition label")

Data Not Collected. This matches `DeviceMonitor/PrivacyInfo.xcprivacy` (no tracking, no collected data types; one required-reason API, `UserDefaults`, reason `CA92.1`).

## App Review notes

- The app needs a Wi‑Fi network with other devices. If the review network has none, enable **Settings › About › Use demo data** and relaunch: the app then shows a sample home network.
- Local Network access is requested with a purpose string. The app does not use the multicast entitlement; discovery uses Bonjour for the declared service types and unicast connection probes.
- IPv6 and hostnames can be added manually. All data stays on the device.

## Screenshots

Produced by the `Screenshots` job in `.github/workflows/build-and-test.yml` from the demo network, light and dark:

| Device | Size (px) | Files |
|---|---|---|
| iPhone 6.9″ (iPhone 18 Pro Max) | 1320 × 2868 | `Media/screenshots/*.png` |
| iPad 13″ (iPad Pro M5) | 2064 × 2752 | `Media/screenshots/ipad-pro-13-inch-m5/*.png` |
| iPhone Duo outer / inner (optional) | 1398 × 2034 / 2007 × 2853 | needs the iOS 27.1 simulator runtime on a Mac |

## App icon

The icon is an Icon Composer file, `DeviceMonitor/AppIcon.icon`: a cobalt gradient background with three layers (the D's bowl, its stem and the mint dot), rendered by the system in default, dark, tinted and clear appearances. CI renders all six appearances into `Media/app-icon-renders/`. Fine-tuning specular and refraction needs Icon Composer on a Mac.
