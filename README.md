# Fedora Image Maker Script

## Overview

The Fedora Image Maker script is designed to facilitate the creation of Fedora images for versions 39, 40, and 41. This script supports multiple modes of operation, including default, mock, dnf, and hack modes. Depending on the selected mode, the script requires different tools and environments to be set up.

## Usage

To run the script with the default settings, simply execute:

```sh
./fedora_image_maker.sh
```

### Supported Modes

- **Default Mode**: Requires `podman` to be installed. This is the standard mode of operation.
- **Mock Mode**: Requires `mock` to be installed. Suitable for building images in a mock environment.
- **DNF Mode**: Typically used on Red Hat-based systems, requiring `dnf` to be installed.
- **Hack Mode**: Similar to the default mode but with specific tweaks. Requires `podman` to be installed.

### Command Options

- `--clean`: Cleans up the build environment, including `podman`, `mock`, and external environments.
- `--test`: Moves the results to the appropriate directory (test function can be customized).
- `--image`: Executes the default image creation process in hack mode using `podman`.
- `--mock`: Builds the image using `mock`.
- `--dnf`: Builds the image using `dnf`.
- `--hack`: Executes the image creation process in hack mode using `podman`.

## Detailed Commands

### Default Mode (Podman)

To create an image using the default mode with `podman`, run:

```sh
./fedora_image_maker.sh
```

### Podman Mode

To build the image specifically with `podman`, run:

```sh
./fedora_image_maker.sh --podman
```

### Clean Mode

To clean up all build environments, run:

```sh
./fedora_image_maker.sh --clean
```

### Test Mode

To test the build and move results, run:

```sh
./fedora_image_maker.sh --test
```

### Mock Mode

To build the image using `mock`, run:

```sh
./fedora_image_maker.sh --mock
```

### DNF Mode

To build the image using `dnf`, run:

```sh
./fedora_image_maker.sh --dnf
```

### Hack Mode

To build the image in hack mode using `podman`, run:

```sh
./fedora_image_maker.sh --hack
```

## Requirements

- **Podman**: Required for default and hack modes.
- **Mock**: Required for mock mode.
- **DNF**: Required for dnf mode.
- **Sudo Privileges**: Required for various operations within the script.

## Logs

The script logs its operations in the `$LOG_DIR` directory. Each mode generates its own log file:

- Default mode: `build.log`
- Podman mode: `image_build.log`
- Mock mode: `mock_build.log`
- Dnf mode: `dnf_build.log`
- Hack mode: `hack_build.log`

## Output

The final image is stored in the current working directory with a name format of `${IMAGE_NAME}_f${VERSION}_${RELEASE_NUM}`.

## Additional Information

For any customizations or further details on the script's internal workings, refer to the script's inline comments and functions.

---

This README provides a concise overview of how to use the Fedora Image Maker script. For further assistance or detailed troubleshooting, consider examining the script itself or reaching out to the community for support.