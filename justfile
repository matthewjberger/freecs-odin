set windows-shell := ["powershell.exe"]

# Displays the list of available commands
@just:
    just --list

# Builds the library
build:
    odin build . -out:freecs.exe

# Runs all tests
test:
    odin test . -all-packages

# Runs the boids example
run:
    odin run examples/boids.odin -file

# Builds the boids example
build-boids:
    odin build examples/boids.odin -file -out:examples/boids.exe

# Runs the boids example in release mode
run-release:
    odin run examples/boids.odin -file -o:speed

# Checks for compilation errors without producing output
check:
    odin check .

# Formats all Odin files (Windows)
[windows]
format:
    Get-ChildItem -Recurse -Filter *.odin | ForEach-Object { odinfmt -w $_.FullName }

# Formats all Odin files (Unix)
[unix]
format:
    find . -name "*.odin" -exec odinfmt -w {} \;

# Cleans build artifacts (Windows)
[windows]
clean:
    Remove-Item -Force -ErrorAction SilentlyContinue freecs.exe, examples/boids.exe

# Cleans build artifacts (Unix)
[unix]
clean:
    rm -f freecs.exe examples/boids.exe

# Displays Odin version
@versions:
    odin version
