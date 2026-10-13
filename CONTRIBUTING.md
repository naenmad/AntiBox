# Contributing to ZedGravity

Thank you for considering contributing to ZedGravity! We welcome community contributions to help improve the developer experience for Zed Editor and AI agents on macOS.

## Code of Conduct

This project adheres to the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Development Setup

### Prerequisites
- macOS 14.0+ (Sonoma or Sequoia)
- Xcode 15.0+ or Command Line Tools (`xcode-select --install`)
- Swift 5.9+

### Building Locally

1. Clone the repository:
   ```bash
   git clone https://github.com/naenmad/ZedGravity.git
   cd ZedGravity
   ```

2. Build and run via Swift Package Manager:
   ```bash
   swift run ZedGravity
   ```

3. Package into `.app` and install to `/Applications`:
   ```bash
   ./scripts/build_app.sh -i
   ```

## Pull Request Guidelines

1. **Focused Changes**: Keep pull requests focused on a single feature, bug fix, or documentation enhancement.
2. **Apple HIG Alignment**: Ensure any UI additions conform to Apple Human Interface Guidelines and clean typography standards.
3. **No External Trackers**: Never introduce third-party telemetry, tracking libraries, or remote proxies.
4. **Testing**: Verify that builds pass cleanly with `./scripts/build_app.sh`.
