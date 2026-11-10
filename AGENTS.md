# AGENTS.md

Guidance for AI coding agents (and people) working in this repository. The [README](README.md) covers what the packages are and how to release them. This file covers how the code is built and the patterns to follow.

## Commands

Run everything from the repository root. You need the .NET 10 SDK (`global.json`) and PowerShell 7 (`pwsh`).

```powershell
./build.ps1                                            # restore, build and pack (Release) into artifacts/packages
dotnet build fieldkit.slnx                             # quick build
dotnet format fieldkit.slnx --verify-no-changes        # formatting check, as CI runs it
dotnet format fieldkit.slnx                            # fix formatting
```

Before you finish a change, run `./build.ps1` with `CI=true` set in the environment (CI treats every warning as an error) and the format check above. Both must pass with 0 warnings.

There is no test project. Most of the code drives Meadow hardware, so a change that touches hardware behavior has to be checked on a device. Say so in the PR rather than claiming it was tested.

## Layout

| Path | What it is |
| --- | --- |
| `fieldkit.slnx` | The solution. Add every new project here. |
| `Directory.Build.props` | Shared package metadata, analyzers, Source Link, symbols, package validation, output to `artifacts/packages`. |
| `Directory.Packages.props` | Central package versions. `MeadowVersion` sets every Meadow package. Never put a `Version` on a `PackageReference`. |
| `NuGet.Config` | Restores from nuget.org only. |
| `.editorconfig` | Code style, enforced on build. |
| `src/FieldKit.<Name>/` | One package per folder: `FieldKit.<Name>.csproj`, a `README.md` that is packed with it, and the code. |
| `.github/workflows/build.yml` | CI build and pack, plus the tag-triggered release. |

## Package rules

- Every package ID starts with `FieldKit.`, and its root namespace matches the package ID.
- Each `.csproj` sets its own `Version`, `Description` and `PackageTags`. Shared metadata stays in `Directory.Build.props`.
- A package that depends on prerelease packages must itself be a prerelease (`0.1.0-beta`). NuGet warns otherwise, and CI turns that warning into an error.
- Packages are general purpose. Nothing tied to one product, device or deployment goes in a package; that belongs in the app that uses it.
- Public API changes are breaking for consumers. Once a version is published, set `PackageValidationBaselineVersion` in the `.csproj` so package validation catches accidental breaks, and bump the version to match the change.

## C# conventions

- File-scoped `namespace` blocks are not used; keep the braced `namespace X { }` style the code already uses.
- Namespaces follow folders: `FieldKit.Meadow`, `FieldKit.Meadow.Controllers`, `FieldKit.Meadow.Services`. Never name a namespace after a type in it.
- `using` directives go outside the namespace, `System` first.
- Seal classes that aren't designed for inheritance, especially `IDisposable` ones; then a plain `Dispose()` is enough.
- Dispose what you own: cancel and dispose each `CancellationTokenSource`, and release pins and ports.
- Don't use `ConfigureAwait(false)` (CA2007 is turned off): Meadow has no synchronization context.
- Catch-all `catch (Exception)` is only for top-level boot, shutdown and background loops, and it must log. Elsewhere, catch specific exceptions.
- Comments explain why, not what. XML docs on public types are welcome but not required (CS1591 is off).
- Don't suppress an analyzer warning without a `Justification` in the `[SuppressMessage]`.

## FieldKit.Meadow patterns

### The app and its lifecycle

`MeadowBase : App<F7FeatherV1>` owns the boot sequence. An app derives from it and supplies only:

- `DefaultDeviceName` (used when `app.config.yaml` has no `App.DeviceName`) and `DeviceType` (reported by `GET /info`).
- `InitializeDevice()`: create and initialize the app's own controllers.
- `DisposeServices()`: release the app's own controllers with `DisposeIfRegistered<T>()`, in the order they must go.

`MeadowBase.Initialize()` runs, in order: startup settings, `LedController` (yellow), diagnostics, LED red, WiFi (external antenna), `WatchdogService`, the app's `InitializeDevice()`, `NetworkService`, `MapleService`, `HeartbeatService`, then WiFi event tracking. `Run()` starts the watchdog and heartbeat and waits for WiFi. `OnNetworkConnected` starts Maple once there is an IP, or rebinds it if DHCP changed the address. Anything that needs an IP goes there, not in `Initialize()`.

When you change the boot order, keep the LED stages in `LedStatus` in step with it.

### Controllers, services and DI

- **Controllers** are hardware-shaped (LED, relay). **Services** are app concerns (Maple, network, diagnostics, watchdog, heartbeat). Both derive from `BaseController` / `BaseService`, take a `Logger` in their constructor, and have a `virtual Task Run()` that does nothing by default.
- Create them with `Services.Create<T>()`, which builds `T` from already-registered instances. Resolution is by registered type only, so **register a dependency before anything that needs it**. Use `Services.Add(instance)` for things you didn't build, such as the WiFi adapter and options objects.
- Use two-phase construction for hardware: the constructor takes dependencies, and a separate `Initialize(...)` touches pins. That keeps the initialization order explicit in `InitializeDevice()`.
- Pass generic `IPin`s into `Initialize(...)`. Only `OnboardRgbLed` uses F7 Feather-specific pins, and it no-ops on other devices.
- `IOnOrOffController` (`TurnOn` / `TurnOff`) is the contract for every switchable output. "On" means active, whatever the electrical polarity.

### Hardware specifics

- `RelayOutput` drives an active-low relay board through an open-drain pin: on pulls the pin low, and off lets it float. The pin starts floating, so the relay is off at boot, and `Dispose()` turns it off before releasing the pin.
- The onboard RGB LED is common anode, so its PWM is inverted.
- `WatchdogService` arms the hardware watchdog for `DefaultTimeoutSeconds` (15) and pets it every `DefaultPetIntervalSeconds` (10) from its own thread, so a slow request can't trip it.
- `HeartbeatService` logs every `DefaultIntervalSeconds` (30) and checks health every `DefaultCheckIntervalSeconds` (3): WiFi is connected, there is an IP, and Maple is running on it. Never set `TestRestartAfterBeats` outside a restart test.

### Maple request handlers

Maple breaks these rules silently, so every handler must follow them:

1. **Return `IActionResult` synchronously, never `async Task<IActionResult>`.** An async handler returns an empty `200` immediately and swallows exceptions. Block on async work with `.GetAwaiter().GetResult()`. That's safe on Meadow, which has no synchronization context.
2. **`QueryString` is `null` when the URL has no `?`.** Read it with `QueryString?["x"]`.
3. **`IsReusable => false`.** Maple keeps per-request state on the handler instance.
4. **Maple creates handlers outside DI.** Resolve controllers from `Resolver.Services` in the constructor, and only types registered before Maple starts.
5. **Return explicit status codes and log each outcome**: `OkResult`, `400` for bad input, `409` when busy, and `ServerErrorResult` for a caught failure. Log accepted requests at Info, rejects at Warn and failures at Error.
6. **Build JSON by hand.** Maple's `JsonResult` serializes by reflection, which Meadow's deploy-time trimming can break (see `DeviceInfo.ToJson`).

`InfoRequestHandler` serves `GET /info` from the package itself; Maple finds it by scanning loaded assemblies. Apps must not add their own `/info` route.

### Logging

- Use `Logger.StartupSection("Title", () => ...)` (or `StartupSectionAsync`) for a boot step, and `Logger.StartupDetail("...")` for extra lines. `App.StartupDetails` in `app.config.yaml` turns the banners off; the work inside a section always runs.
- Controllers log `"<Name> is initialized."` at Info.

### Consumers' deploy settings

An app that uses FieldKit.Meadow must list it in `app.build.yaml` under `Deploy: NoLink: [ FieldKit.Meadow ]`. Otherwise Meadow trims constructors that are only reached through `Services.Create<T>()`. Keep this in the package README whenever you change how types are created.

## CI and releases

- `.github/workflows/build.yml` runs `build.ps1` and the format check on every push to `main` and every pull request.
- A tag named `<PackageId>-v<Version>` releases that package: it must match the `.csproj` `Version`. nuget.org publishing uses Trusted Publishing with the `NUGET_USER` repository variable; never add an API key secret.
- Keep every action on its newest major version, so runs show no deprecation warnings.

## Writing docs and PRs

- READMEs, this file, comments and PR descriptions describe the current state only. Don't mention where code came from or what it used to be called.
- Update the package README and this file in the same change when you change a pattern they describe.
