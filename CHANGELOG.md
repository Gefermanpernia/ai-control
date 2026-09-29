# Changelog

## [0.5.1](https://github.com/Gefermanpernia/ai-control/compare/v0.5.0...v0.5.1) (2026-09-29)


### Bug Fixes

* **linux:** check the Claude storage contract without the slow Data search ([#95](https://github.com/Gefermanpernia/ai-control/issues/95)) ([896fcf9](https://github.com/Gefermanpernia/ai-control/commit/896fcf99361036a00c948e7f1f71789e26f7d8e4)), closes [#94](https://github.com/Gefermanpernia/ai-control/issues/94)
* **tui:** show each options screen's own keys in the footer ([#90](https://github.com/Gefermanpernia/ai-control/issues/90)) ([46d84ac](https://github.com/Gefermanpernia/ai-control/commit/46d84ac5e6892b92a6541fcce7363d5afa962732)), closes [#89](https://github.com/Gefermanpernia/ai-control/issues/89)

## [0.5.0](https://github.com/Gefermanpernia/ai-control/compare/v0.4.0...v0.5.0) (2026-09-28)


### Features

* **auto-switch:** decide the next account near a usage limit in the engine ([#71](https://github.com/Gefermanpernia/ai-control/issues/71)) ([faec3b4](https://github.com/Gefermanpernia/ai-control/commit/faec3b412d060b3def01d559e47cb5965cee113e))
* **auto-switch:** report check results as data and show repeated menu notices once ([#85](https://github.com/Gefermanpernia/ai-control/issues/85)) ([3ede1c2](https://github.com/Gefermanpernia/ai-control/commit/3ede1c22a861ef1eca8b9e53e5c66659fd4d57bb)), closes [#82](https://github.com/Gefermanpernia/ai-control/issues/82)
* **linux:** refresh usage in the background with a systemd user timer ([#76](https://github.com/Gefermanpernia/ai-control/issues/76)) ([0257544](https://github.com/Gefermanpernia/ai-control/commit/02575448b31340663335cc131d671a67e95943fd))
* **menu:** control refresh, automatic switching and account priority from the menu ([#81](https://github.com/Gefermanpernia/ai-control/issues/81)) ([f472d8b](https://github.com/Gefermanpernia/ai-control/commit/f472d8b1471c06e35a6c2a0fb5097088992eef79))
* **menu:** refresh usage periodically while the menu window is open ([#69](https://github.com/Gefermanpernia/ai-control/issues/69)) ([46b10f6](https://github.com/Gefermanpernia/ai-control/commit/46b10f6fe4e06fb180a5ceab2c2f34371d6051c8))
* **menu:** run the automatic switch check and background refresh ([#79](https://github.com/Gefermanpernia/ai-control/issues/79)) ([5055f8a](https://github.com/Gefermanpernia/ai-control/commit/5055f8af8e8c1cb97689811ea62c133d882b7a3d))
* **menu:** show usage monitors after the accounts ([#56](https://github.com/Gefermanpernia/ai-control/issues/56)) ([1e38538](https://github.com/Gefermanpernia/ai-control/commit/1e38538ba9f377792910b224369b5557586a6eaa))
* **monitors:** report NaN usage per model in the status JSON ([#44](https://github.com/Gefermanpernia/ai-control/issues/44)) ([10421c1](https://github.com/Gefermanpernia/ai-control/commit/10421c1e08f9e6924eaafb66def140cefcb5e72f))
* **monitors:** report OpenCode Go usage in the status JSON ([#38](https://github.com/Gefermanpernia/ai-control/issues/38)) ([c580f03](https://github.com/Gefermanpernia/ai-control/commit/c580f03902e89316802cbf90b3a1cee13f02e01e))
* **settings:** store refresh and automatic switching options in the engine ([#63](https://github.com/Gefermanpernia/ai-control/issues/63)) ([e298bf4](https://github.com/Gefermanpernia/ai-control/commit/e298bf4073c891c1cc978f35a5f858e91bbbe40f))
* **tui:** change refresh and automatic switching options from an options screen ([#78](https://github.com/Gefermanpernia/ai-control/issues/78)) ([d56c64d](https://github.com/Gefermanpernia/ai-control/commit/d56c64d65634483d06de12f465d08967d83ef0dc))
* **tui:** order accounts by priority and ask the engine to switch at the limit ([#75](https://github.com/Gefermanpernia/ai-control/issues/75)) ([82d467c](https://github.com/Gefermanpernia/ai-control/commit/82d467cbad30b841ab80907b3658555ccce4c4d6))
* **tui:** quit with Ctrl+C and color usage green, yellow and red ([#37](https://github.com/Gefermanpernia/ai-control/issues/37)) ([6113e29](https://github.com/Gefermanpernia/ai-control/commit/6113e29194aead0025c67b4fc2fe5456017755a9)), closes [#36](https://github.com/Gefermanpernia/ai-control/issues/36)
* **tui:** refresh usage periodically while the terminal UI is open ([#67](https://github.com/Gefermanpernia/ai-control/issues/67)) ([0ece9c7](https://github.com/Gefermanpernia/ai-control/commit/0ece9c710b3cd88fe55c66730b245b4aef51df17))
* **tui:** show usage monitors below the accounts ([#50](https://github.com/Gefermanpernia/ai-control/issues/50)) ([56746a5](https://github.com/Gefermanpernia/ai-control/commit/56746a53b4c5fa341a64b9c10a010e77a35ace06))


### Bug Fixes

* **linux:** read owner-only login files through one checked descriptor ([#43](https://github.com/Gefermanpernia/ai-control/issues/43)) ([bc6f59f](https://github.com/Gefermanpernia/ai-control/commit/bc6f59f89a18493f392fe57d8190f31b6d3f5667))
* **linux:** renew logins in a private, unpredictable temporary directory ([#55](https://github.com/Gefermanpernia/ai-control/issues/55)) ([92b66d9](https://github.com/Gefermanpernia/ai-control/commit/92b66d961e34ebc94b09349d35b85234d4a24be5)), closes [#54](https://github.com/Gefermanpernia/ai-control/issues/54)
* **monitors:** round token counts before choosing the unit ([#65](https://github.com/Gefermanpernia/ai-control/issues/65)) ([1f8aeb1](https://github.com/Gefermanpernia/ai-control/commit/1f8aeb1ccd437ac8900d852ae2bc81cb90ebb5f2))
* **tui:** fit the key hints to the terminal width ([#58](https://github.com/Gefermanpernia/ai-control/issues/58)) ([3386e7d](https://github.com/Gefermanpernia/ai-control/commit/3386e7d67fc4aaadb2b0d70eebfd6bc6144a84a7)), closes [#57](https://github.com/Gefermanpernia/ai-control/issues/57)
* **tui:** show the underlying error when an engine command fails ([#46](https://github.com/Gefermanpernia/ai-control/issues/46)) ([7e0b7c9](https://github.com/Gefermanpernia/ai-control/commit/7e0b7c974d3a95f22c7539d38818048d15d6b561))

## [0.4.0](https://github.com/Gefermanpernia/ai-control/compare/v0.3.1...v0.4.0) (2026-09-27)


### Features

* **tui:** save the account you are signed in to with s ([#34](https://github.com/Gefermanpernia/ai-control/issues/34)) ([bd418ca](https://github.com/Gefermanpernia/ai-control/commit/bd418ca404c27d06a06ca30c0c264ff0a2ebff32)), closes [#33](https://github.com/Gefermanpernia/ai-control/issues/33)

## [0.3.1](https://github.com/Gefermanpernia/ai-control/compare/v0.3.0...v0.3.1) (2026-09-27)


### Bug Fixes

* **tui:** explain a missing engine and show only the providers the user has ([#31](https://github.com/Gefermanpernia/ai-control/issues/31)) ([4bceba7](https://github.com/Gefermanpernia/ai-control/commit/4bceba7fd74a4631ca7e543a8f7306d8486d5398)), closes [#30](https://github.com/Gefermanpernia/ai-control/issues/30)

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
