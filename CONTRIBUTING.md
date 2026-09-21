# Contributing to MDEditorKit

Thank you for your interest in contributing to **MDEditorKit**! MDEditorKit is a native macOS Markdown editor component built on TextKit 2.

We welcome bug reports, performance enhancements, documentation improvements, and pull requests.

---

## Code of Conduct

All contributors and participants are expected to adhere to our [Code of Conduct](CODE_OF_CONDUCT.md). Please report unacceptable behavior to **xuanlian@mac.com**.

---

## Development Setup

### Prerequisites
- macOS 14.0+ (macOS 15+ recommended)
- Xcode 16.0+ / Swift 6.0+ command line tools

### Getting Started
1. Fork the repository and clone your fork locally:
   ```bash
   git clone https://github.com/<your-username>/MDEditorKit.git
   cd MDEditorKit
   ```
2. Build the package:
   ```bash
   swift build
   ```
3. Run the automated test suite:
   ```bash
   swift test
   ```

---

## Contribution Guidelines

1. **Always Target `main`**: All feature branches and pull requests must branch from and target `main` (never `master`).
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. **Swift 6 Concurrency & Architecture**:
   - Comply strictly with Swift 6 Concurrency rules (Strict Concurrency Checking).
   - Keep public API surfaces clean, well-documented with DocC comments, and modular.
   - Maintain zero unnecessary dependencies.

3. **Testing**:
   - Any new functionality or bugfix must include corresponding automated tests (`swift test`).
   - Ensure all existing tests pass before submitting a PR.
4. **Commit Conventions**:
   - Follow Conventional Commits (`feat: ...`, `fix: ...`, `docs: ...`, `test: ...`).
5. **Submitting a Pull Request**:
   - Push your branch to your fork and submit a PR targeting `main`.
   - Include a concise explanation of changes and verification steps.

---

## License

By contributing to MDEditorKit, you agree that your contributions will be licensed under the [Mozilla Public License Version 2.0](LICENSE).
