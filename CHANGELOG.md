# Changelog

## [0.0.2]

* **Tool Self-Update Awareness**: The CLI now automatically checks for updates to `pub_doctor` itself and notifies you when a newer version is available.
* **Alternative Package Suggestions**: High-risk dependencies now automatically suggest healthier, better-maintained alternatives from pub.dev.
* **WASM Compatibility**: Fully refactored core architecture to support `dart2wasm` and web platforms while maintaining CLI performance.


## [0.0.1] — Initial Release


* Initial public release of pub_doctor
* Added dependency health analysis for Dart and Flutter projects
* Added dependency risk scoring system
* Added CLI for scanning project dependencies
* Added GitHub and pub.dev metadata analysis
* Added local caching and offline support
* Added CI-friendly usage and JSON output
* Added `pub_doctor update` command to auto-resolve and upgrade mutually compatible packages
