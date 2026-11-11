# FieldKit

Reusable .NET building blocks for small networked devices. Each board family gets its own NuGet package under the `FieldKit.` prefix.

| Package | What it is |
| --- | --- |
| [`FieldKit.Meadow`](src/FieldKit.Meadow/README.md) | Starter kit for Meadow F7 Feather devices: a base app that owns the boot sequence (status LED, diagnostics, WiFi, watchdog, heartbeat, Maple web server with UDP discovery and `GET /info`), plus relay and on/off controllers. |

## Building the packages

You need the .NET 10 SDK and PowerShell 7 (`pwsh`, on Windows, macOS or Linux). From the repository root:

```powershell
./build.ps1
```

It restores, builds and packs `fieldkit.slnx` in Release and puts every `.nupkg` (and its `.snupkg` symbols package) in `artifacts/packages`. Pass `-Configuration Debug` for a debug build.

To try a package in another project before publishing it, add `artifacts/packages` as a local NuGet source:

```bash
dotnet nuget add source /path/to/fieldkit/artifacts/packages --name fieldkit-local
```

## Releasing

GitHub Actions (`.github/workflows/build.yml`) builds and packs on every push to `main` and every pull request, and keeps the packages as a workflow artifact.

To release a package, set its `<Version>` in its `.csproj`, merge, then push a tag named `<PackageId>-v<Version>`:

```bash
git tag FieldKit.Meadow-v0.1.0-beta
git push origin FieldKit.Meadow-v0.1.0-beta
```

Or, without a clone, on GitHub: **Releases**, **Draft a new release**, type `FieldKit.Meadow-v0.1.0-beta` as a new tag on `main`, and **Publish release**. The workflow attaches the packages to that release.

The workflow checks the tag matches the `.csproj` version, then:

- creates a GitHub Release for the tag with the `.nupkg`, the `.snupkg` symbols package and a zip of the assembly (`.dll`, `.pdb`, `.xml`). A version with a suffix such as `-beta` is marked as a prerelease.
- pushes the package to GitHub Packages, at `https://nuget.pkg.github.com/NelsonLamprecht/index.json`.

## Using the packages from GitHub Packages

GitHub Packages needs a sign-in even to download, so each machine that restores needs a GitHub token once:

1. Create a classic personal access token at [github.com/settings/tokens](https://github.com/settings/tokens) with only the `read:packages` scope.
2. Add the feed to your user-level NuGet config (not the repository's), under the source name `fieldkit`:

   ```powershell
   dotnet nuget add source https://nuget.pkg.github.com/NelsonLamprecht/index.json --name fieldkit --username <your GitHub username> --password <token>
   ```

   On macOS and Linux, add `--store-password-in-clear-text`; Windows encrypts it.

In the consuming repository, add a `NuGet.Config` that declares the same `fieldkit` source and maps `FieldKit.*` to it, so only FieldKit packages come from GitHub:

```xml
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
    <add key="fieldkit" value="https://nuget.pkg.github.com/NelsonLamprecht/index.json" />
  </packageSources>
  <packageSourceMapping>
    <packageSource key="nuget.org"><package pattern="*" /></packageSource>
    <packageSource key="fieldkit"><package pattern="FieldKit.*" /></packageSource>
  </packageSourceMapping>
</configuration>
```

In GitHub Actions in another repository, pass `${{ secrets.GITHUB_TOKEN }}` as the password and give that repository access in the package's settings (Manage Actions access).

## Publishing to nuget.org

The release can also push to nuget.org using [Trusted Publishing](https://learn.microsoft.com/nuget/nuget-org/trusted-publishing), so no API key is stored anywhere. To turn it on:

1. On nuget.org, open your account's **Trusted Publishing** page and add a policy for repository owner `NelsonLamprecht`, repository `fieldkit`, workflow file `build.yml`.
2. In this repository, add an Actions **variable** (Settings, Secrets and variables, Actions, Variables) named `NUGET_USER` with your nuget.org username.

Without `NUGET_USER`, releases are GitHub only.

To publish to nuget.org by hand instead:

```bash
dotnet nuget push "artifacts/packages/*.nupkg" --api-key <your key> --source https://api.nuget.org/v3/index.json
```

The `.snupkg` symbols packages are pushed alongside automatically.

## Layout

- `fieldkit.slnx`: the solution.
- `Directory.Build.props`: metadata every package shares (author, license, repository, Source Link, symbols, output folder).
- `Directory.Packages.props`: central package versions; `MeadowVersion` moves every Meadow package at once.
- `src/<PackageId>/`: one folder per package. Each `.csproj` sets its own `Version`, `Description` and `PackageTags`, so packages are released independently.

To add a package, create `src/FieldKit.<Name>/FieldKit.<Name>.csproj` with `IsPackable`, `PackageId`, `Version`, `Description` and a `README.md`, then add it to `fieldkit.slnx`.
