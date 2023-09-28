# ClamAV Docker Repository

We publish the following Docker images for the ClamAV project:

* [`clamav`](https://hub.docker.com/r/clamav/clamav/tags): The official ClamAV Docker image.

  Based on Alpine Linux.

  Readme for the [`clamav` image is here](./clamav/README-alpine.md).

* [`clamav-debian`](https://hub.docker.com/r/clamav/clamav-debian/tags): This is a multi-arch image for amd64, arm64, and ppc64le. *This may eventually replace the Alpine-based image.*

  Based on Debian Linux.

  Readme for the [`clamav-debian` image is here](./clamav/README-debian.md).

* [`clamav-bytecode-compiler`](https://hub.docker.com/r/clamav/clambc-compiler/tags): This image is for use with compiling ClamAV bytecode signatures. Bytecode signatures do allow for more complex logic than traditional signatures. But, bytecode signatures are difficult to write and use a lot of CPU. For this reason, they are rarely used. Most ClamAV signature authors will never need to write a bytecode signature.

  Based on Ubuntu Linux.

  Readme for the [`clamav-bytecode-compiler` image is here](./clamav-bytecode-compiler/README.md).
