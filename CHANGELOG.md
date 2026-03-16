# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 2026-03-16

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`cli_launcher` - `v0.3.3`](#cli_launcher---v033)

---

#### `cli_launcher` - `v0.3.3`

 - **FEAT**: Flutter workspace support, comprehensive e2e matrix tests, and CI cleanup ([#22](https://github.com/blaugold/cli_launcher/issues/22)). ([119e7e1f](https://github.com/blaugold/cli_launcher/commit/119e7e1f4d24c4a3c8ef2f922d745225e945b122))

## 0.3.3

 - **FEAT**: Flutter workspace support, comprehensive e2e matrix tests, and CI cleanup ([#22](https://github.com/blaugold/cli_launcher/issues/22)). ([119e7e1f](https://github.com/blaugold/cli_launcher/commit/119e7e1f4d24c4a3c8ef2f922d745225e945b122))


## 2026-03-14

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`cli_launcher` - `v0.3.2+2`](#cli_launcher---v0322)

---

#### `cli_launcher` - `v0.3.2+2`

 - **FIX**: support path-activated workspace packages ([#18](https://github.com/blaugold/cli_launcher/issues/18)). ([1cf4792d](https://github.com/blaugold/cli_launcher/commit/1cf4792df70c42924db4a9eea6109f3e2f8a5303))
 - **FIX**: format test/e2e_test.dart. ([b38182e1](https://github.com/blaugold/cli_launcher/commit/b38182e12b540cedb7a68adf1e0908cb6b64d6aa))
 - **FIX**: prevent `dart run` auto-resolution from interfering with pubspec timestamp tests. ([2e88783b](https://github.com/blaugold/cli_launcher/commit/2e88783b53cd7d49d87b88bd7b77fd5a1def7524))
 - **FIX**: treat equal timestamps as up-to-date in `_pubspecLockIsUpToDate` ([#16](https://github.com/blaugold/cli_launcher/issues/16)). ([44bd9f34](https://github.com/blaugold/cli_launcher/commit/44bd9f349650b388f3f286742b468d23f1bf9172))
 - **FIX**: format lib/cli_launcher.dart. ([179ee73e](https://github.com/blaugold/cli_launcher/commit/179ee73edf06d72203247f08c1cc5d54b1c7de24))
 - **FIX**: Support binaries installed by `dart install` ([#19](https://github.com/blaugold/cli_launcher/issues/19)). ([b342628c](https://github.com/blaugold/cli_launcher/commit/b342628c6ca2e757fbd4651a192fbc95bae2189e))

## 0.3.2+2

 - **FIX**: support path-activated workspace packages ([#18](https://github.com/blaugold/cli_launcher/issues/18)). ([1cf4792d](https://github.com/blaugold/cli_launcher/commit/1cf4792df70c42924db4a9eea6109f3e2f8a5303))
 - **FIX**: format test/e2e_test.dart. ([b38182e1](https://github.com/blaugold/cli_launcher/commit/b38182e12b540cedb7a68adf1e0908cb6b64d6aa))
 - **FIX**: prevent `dart run` auto-resolution from interfering with pubspec timestamp tests. ([2e88783b](https://github.com/blaugold/cli_launcher/commit/2e88783b53cd7d49d87b88bd7b77fd5a1def7524))
 - **FIX**: treat equal timestamps as up-to-date in `_pubspecLockIsUpToDate` ([#16](https://github.com/blaugold/cli_launcher/issues/16)). ([44bd9f34](https://github.com/blaugold/cli_launcher/commit/44bd9f349650b388f3f286742b468d23f1bf9172))
 - **FIX**: format lib/cli_launcher.dart. ([179ee73e](https://github.com/blaugold/cli_launcher/commit/179ee73edf06d72203247f08c1cc5d54b1c7de24))
 - **FIX**: Support binaries installed by `dart install` ([#19](https://github.com/blaugold/cli_launcher/issues/19)). ([b342628c](https://github.com/blaugold/cli_launcher/commit/b342628c6ca2e757fbd4651a192fbc95bae2189e))


## 2025-08-03

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`cli_launcher` - `v0.3.2+1`](#cli_launcher---v0321)

---

#### `cli_launcher` - `v0.3.2+1`

 - **DOCS**: add `example/README.md`. ([f8c6457e](https://github.com/blaugold/cli_launcher/commit/f8c6457e2641f71fd80920e999be6f71f38de1de))

## 0.3.2+1

 - **DOCS**: add `example/README.md`. ([f8c6457e](https://github.com/blaugold/cli_launcher/commit/f8c6457e2641f71fd80920e999be6f71f38de1de))


## 2025-08-03

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`cli_launcher` - `v0.3.2`](#cli_launcher---v032)

---

#### `cli_launcher` - `v0.3.2`

 - **FEAT**: add LocalLaunchConfig support for customizable pub get and dart run args ([#12](https://github.com/blaugold/cli_launcher/issues/12)). ([9c3f21d6](https://github.com/blaugold/cli_launcher/commit/9c3f21d6723cb7ca77ba8218cf9f73e8109d75b0))

## 0.3.2

 - **FEAT**: add LocalLaunchConfig support for customizable pub get and dart run args ([#12](https://github.com/blaugold/cli_launcher/issues/12)). ([9c3f21d6](https://github.com/blaugold/cli_launcher/commit/9c3f21d6723cb7ca77ba8218cf9f73e8109d75b0))

## 0.3.1

 - **FEAT**: lower version constraint for `path`. ([daf9a9c9](https://github.com/blaugold/cli_launcher/commit/daf9a9c9e50adb8eeb194393a1ca85a4dbe7200b))

## 0.3.0

> Note: This release has breaking changes.

 - **BREAKING** **FEAT**: pass launch context as argument ([#8](https://github.com/blaugold/cli_launcher/issues/8)). ([6a1e2baf](https://github.com/blaugold/cli_launcher/commit/6a1e2baf1c6bf3e8cd5df80a9d5d4b239b7e0b5a))

## 0.2.1

 - **FEAT**: improve support for path dependencies ([#7](https://github.com/blaugold/cli_launcher/issues/7)). ([4559db92](https://github.com/blaugold/cli_launcher/commit/4559db92d9e92a6b8c415ee51d204c889471a3e6))

## 0.2.0

> Note: This release has breaking changes.

 - **BREAKING** **FEAT**: full rewrite ([#6](https://github.com/blaugold/cli_launcher/issues/6)). ([ab11a1cf](https://github.com/blaugold/cli_launcher/commit/ab11a1cf6f401c27a3f698fef2689447408f3282))

## 0.1.1

 - **FEAT**: lower SDK min constraint to 2.12.0 ([#4](https://github.com/blaugold/cli_launcher/issues/4)). ([1bdbdfd2](https://github.com/blaugold/cli_launcher/commit/1bdbdfd22002b2fb344ec2c07900b89298d92f24))

# 0.1.0

Initial release
