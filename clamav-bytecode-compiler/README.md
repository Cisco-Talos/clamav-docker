# ClamAV Bytecode Compiler Docker image

For ease of access, the bytecode compiler has been published to Docker Hub under: [clamav/clambc-compiler](https://hub.docker.com/r/clamav/clambc-compiler/tags)

## Running through Docker

Starting with this beta, the bytecode compiler can be found in a container can be found on Docker Hub in the `clamav/clambc-compiler` repository.

Run the following to download the image, start the container, and get a shell:
```
docker run -v `pwd`:/src -it clamav/clambc-compiler:stable /bin/bash
```

This command will also mount your current directory in the container under the `/src` directory so that you can use the compiler to compile any files in your current directory.

Once inside the Docker container, `clambc-compiler` will be in the `PATH`. To use the compiler, simply run:
```
clambc-compiler --help
```

## Options

The options directly supported by the compiler are below.
```
# clambc-compiler -h
Usage: clambc-compiler [options]

Options:
  -h, --help            show this help message and exit
  -V, --version
  -o OUTFILE, --outfile=OUTFILE
  --save-tempfiles
  -v, --verbose
  --clang-version=CLANGVERSION
  --llvm-version=LLVMVERSION
  --clang-binary=CLANGBINARY
                        Path to clang binary
  --opt-binary=OPTBINARY
                        Path to opt binary
  -I INCLUDES
  -D DEFINES
  --disable-common-warnings
                        -Wno-backslash-newline-escape   -Wno-pointer-sign
                        -Wno-return-type   -Wno-incompatible-pointer-types
                        -Wno-unused-value   -Wno-shift-negative-value   -Wno-
                        implicit-function-declaration   -Wno-incompatible-
                        library-redeclaration   -Wno-implicit-int   -Wno-
                        constant-conversion  (Found in some bytecode
                        signatures).
```

## Additional Notes About the Options

* `--save-tempfiles`

  This option saves all temporary files used by `clambcc` to generate the signature.  It is only useful for debugging or to satisfy someone's curiosity.  If enabled, the files will be stored in `.__clambc_tmp`.

* `--verbose`

  If enabled, `clambcc` will output the commands it is running to generate the executables.

* `--disable-common-warnings`

  There are several warnings clang omits that are common in a lot of the signatures that were used for testing.  This option is to silence them.  It defaults to off.  The warnings are:
    * `Wno-backslash-newline-escape`
    * `Wno-pointer-sign`
    * `Wno-return-type`
    * `Wno-incompativle-pointer-types`
    * `Wno-unused-value`

## Compiler-specific Options

All unrecognized options are assumed to be compiler options, and are passed through to the compiler frontend.  This means that anything supported by `clang` is supported by `clambc-compiler`.
