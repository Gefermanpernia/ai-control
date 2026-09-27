# Changelog

## [0.3.0](https://github.com/Gefermanpernia/ai-control/compare/v0.2.0...v0.3.0) (2026-09-27)


### Features

* **tui:** align logins, show relative update time, color usage by level ([#26](https://github.com/Gefermanpernia/ai-control/issues/26)) ([34718d6](https://github.com/Gefermanpernia/ai-control/commit/34718d63cc6bdc4020d22a2b03d4424fa02052ea))
* **wsl:** run on Windows through WSL without using Windows-side CLIs ([#25](https://github.com/Gefermanpernia/ai-control/issues/25)) ([a1b9476](https://github.com/Gefermanpernia/ai-control/commit/a1b947682dd455bff7c62d6091d43aeeda7ac183)), closes [#20](https://github.com/Gefermanpernia/ai-control/issues/20)


### Bug Fixes

* **linux:** create the data directory on first use so Codex accounts can be added ([#28](https://github.com/Gefermanpernia/ai-control/issues/28)) ([0e3002a](https://github.com/Gefermanpernia/ai-control/commit/0e3002a9716758dc5f59f362f6918154175bb63e))

## [0.2.0](https://github.com/Gefermanpernia/ai-control/compare/v0.1.0...v0.2.0) (2026-09-27)


### Features

* **linux:** build and test the engine on Linux ([#2](https://github.com/Gefermanpernia/ai-control/pull/2)) ([e6c9dc0](https://github.com/Gefermanpernia/ai-control/commit/e6c9dc08067d2ebe8b443802615a750eaf8750ed))
* **linux:** add a versioned JSON status and engine-backed add commands ([#6](https://github.com/Gefermanpernia/ai-control/pull/6)) ([0a5df74](https://github.com/Gefermanpernia/ai-control/commit/0a5df74d00b5d22d5e1472fa3be22d5db6abf954))
* **tui:** add the engine client for the terminal UI ([#7](https://github.com/Gefermanpernia/ai-control/pull/7)) ([128a749](https://github.com/Gefermanpernia/ai-control/commit/128a74918f9846050391aceface3aa0b5eb6c289))
* **tui:** add the terminal UI state machine ([#8](https://github.com/Gefermanpernia/ai-control/pull/8)) ([8012062](https://github.com/Gefermanpernia/ai-control/commit/801206281ddc022bc2de9179429d027d52fe2fba))
* **tui:** render the terminal UI and run its event loop ([#9](https://github.com/Gefermanpernia/ai-control/pull/9)) ([3ef29de](https://github.com/Gefermanpernia/ai-control/commit/3ef29de7892dc6594e43b7abe477d4c1b3b6f7f4))
* **linux:** ship .deb and Arch packages with the terminal UI ([#11](https://github.com/Gefermanpernia/ai-control/pull/11)) ([308e9b6](https://github.com/Gefermanpernia/ai-control/commit/308e9b6814d0053ec751dd2c0b28fac32b1a5dab))


### Bug Fixes

* **linux:** do not build an empty Arch debug package ([#11](https://github.com/Gefermanpernia/ai-control/pull/11)) ([3c53df3](https://github.com/Gefermanpernia/ai-control/commit/3c53df334df42f745f779c6da080abf1e25685de))
* **tui:** act on the login chosen when confirming or renaming ([#8](https://github.com/Gefermanpernia/ai-control/pull/8)) ([942c073](https://github.com/Gefermanpernia/ai-control/commit/942c0735e4372ab434634561b8dce4e917aa4dba))
* **tui:** keep the selected login visible in each provider box ([#9](https://github.com/Gefermanpernia/ai-control/pull/9)) ([a45d4b0](https://github.com/Gefermanpernia/ai-control/commit/a45d4b0b97ceec13dfa13357fd23b1cdb07aeb4e))
