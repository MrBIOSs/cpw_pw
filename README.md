# CPW Patcher — A modern patcher for game clients

[![Dart](https://img.shields.io/badge/Dart-3.10+-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> A **secure** and **fast** patcher for managing Perfect World game client updates. Fully compatible with the original protocol, but with a modern architecture and type safety.

---

## Table of contents

- [Possibilities](#possibilities)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Command CLI](#command-cli)
- [Examples of use](#examples-of-use)
- [Docker](#docker)
- [Safety](#safety)
- [Troubleshooting](#troubleshooting)
- [Migrating from Java](#migrating-from-Java)

---

## Possibilities

| Feature | Description |
|---------|-------------|
| **RSA Signing** | Key generation (1024-bit), manifest signing via MD5withRSA |
| **MySQL/PostgreSQL** | Abstract database layer, parameterized queries, and migrations |
| **File Packing** | `[4-byte LE size][deflate(data)]` format for client compatibility |
| **Incremental Patches** | Automated generation of `v-N.inc` for fast updates |
| **Docker-ready** | Minimal footprint images and health checks |

### Roadmap
- [ ] Integrate CPW into the **Web Admin Panel**
- [ ] Upgrade RSA signature size to **2048-bit**
- [ ] Migrate from MD5withRSA to **SHA-256withRSA**

---

## Architecture

```
lib/
├── app/                          # Entry point and dispatching
│   ├── cli_runner.dart           # Argument parsing and command execution
│   ├── command_info.dart         # Command metadata
│   └── command_registry.dart     # Command registry + menu output
│
├── config/                       # Configuration
│   ├── config.dart               # Exports
│   ├── patcher_config.dart       # Typed immutable model
│   ├── config_loader.dart        # Loading .conf + env overrides
│   └── config_parser.dart        # Parsing .properties
│
├── core/                                # Infrastructure and shared services
│   ├── crypto/                          # Cryptography and encoding
│   │   ├── crypto.dart                  # Crypto module exports
│   │   ├── exceptions.dart              # Typed encryption errors
│   │   ├── file_key_storage.dart        # Implementation keys.json
│   │   ├── key_storage_interface.dart   # Key storage abstraction
│   │   ├── models/
│   │   │   └── rsa_key_pair.dart        # Key pair model  (Public/Private)
│   │   └── utils/
│   │       ├── base64_path_encoder.dart # Path encoding
│   │       └── rsa_utils.dart           # RSA helpers
│   │
│   ├── database/                      # Database management
│   │   ├── database.dart              # DB module exports
│   │   ├── database_interface.dart    # IDatabase (abstraction)
│   │   ├── db_service.dart            # DB business logic
│   │   ├── exceptions.dart            # Typed DB errors
│   │   ├── utils/
│   │   │   └── sql_script_parser.dart # SQL script helper
│   │   └── adapters/
│   │       ├── mysql_adapter.dart     # MySQL implementation
│   │       └── postgres_adapter.dart  # PostgreSQL implementation
│   │
│   ├── logger/
│   │   └── logger_service.dart      # Logging: console + files
│   │
│   └── utils/
│       ├── ansi_colors.dart      # Terminal colors
│       ├── safe_path.dart        # Paths safety
│       └── utilities.dart        # Shared project utilities
│
├── di/                           # Dependency Injection
│   └── service_locator.dart      # get_it locator configuration
│
└── features/                        # Business features (isolated modules)
    ├── revisions/                   # Version and revision management
    │   ├── manifest_service.dart    # Generation of files.md5 + v-N.inc
    │   ├── packer_service.dart      # Packing [size][deflate]
    │   ├── revisions.dart           # Revision module exports
    │   ├── revision_service.dart    # Revision logic: initial, new
    │   ├── commands/
    │   │   ├── initial_command.dart # ./cpw initial
    │   │   ├── listgen_command.dart # ./cpw listgen
    │   │   └── new_command.dart     # ./cpw new
    │   └── models/
    │       └── revision_state.dart  # Revision state
    │
    ├── security/                       # Security and binary patching
    │   ├── binary_patcher_service.dart # Key injection into binaries
    │   ├── rsa_service.dart            # Generation + signing
    │   ├── security.dart               # Security module exports
    │   └── commands/
    │       ├── patch_command.dart      # ./cpw x [exe]
    │       └── rsagen_command.dart     # ./cpw rsagen
    │
    └── setup/                       # Initialization and deployment
        ├── setup.dart               # Initialization module exports
        ├── setup_service.dart       # System initialization
        ├── validators.dart          # Environment validation
        └── commands/
            └── install_command.dart # ./cpw install
```

### Design Principles

- **Feature-first**: Code is grouped around business capabilities.
- **Dependency Inversion**: Business logic depends on abstractions, not implementations.
- **Single Responsibility**: Each class has a single, well-defined purpose.

---

## Requirements

| Component | Version | Purpose |
|-----------|---------|---------|
| **Dart SDK** | ≥ 3.10.0 | Records, pattern matching, async/await |
| **MySQL** | ≥ 5.7 | Storing file metadata and revisions |
| **Docker** | ≥ 24.0 | Optional: for containerization |

### Environment Verification

```bash
# Dart
dart --version  # Dart SDK version: 3.10.0 or later

# MySQL
mysql --version  # mysql  Ver 8.x or 5.7.x
```

---

## Installation

### 1. Cloning a repository

```bash
git clone https://github.com/MrBIOSs/cpw_pw.git
cd cpw_pw
```

### 2. Installing dependencies

```bash
dart pub get
```

### 3. Building an executable file (AOT)

```bash
# For Windows
dart compile exe bin/cpw.dart -o bin/cpw.exe

# For Linux
dart compile exe bin/cpw.dart -o bin/cpw

# verification
./bin/cpw
```

### (Optional) Download the finished binary file on Linux

```bash
curl -L -s "https://github.com/MrBIOSs/cpw_pw/releases/latest/download/cpw" -o ./cpw
```

---

## Configuration

### File structure

```
./
├── config/
│   ├── patcher.conf         # Main configuration settings
│   ├── install_mysql.sql    # Database initialization script
│   ├── install_postgres.sql # Database initialization script
│   └── keys.json            # RSA keys
├── files/
│   ├── new/              # Input: Source files from developers
│   │   ├── element/
│   │   ├── launcher/
│   │   └── patcher/
│   └── CPW/              # Output: Files ready for distribution
│       ├── element/
│       ├── launcher/
│       └── patcher/
├── log/                  # Application logs
│   ├── console.log
│   └── errors.log
└── bin/cpw               # Executable binary
```

### `config/patcher.conf` - basic settings

```ini
# DB connection
db-host=localhost
db-port=3306
db-name=pw
db-user=user
db-password=password

# Paths (relative to baseDir)
patch-path=files
patch-new-dir=new
patch-cpw-dir=CPW

# Minimum client versions
min-element-ver=1
min-launcher-ver=1
min-patcher-ver=1

# Flags
remove-folders=true
remove-files=true
add-size=true
```

### Overriding via environment variables

```bash
# Docker / CI / Production
export DB_HOST=db.prod.internal
export DB_PASSWORD=${VAULT_DB_PASSWORD}

./bin/cpw install
```

Supported Variables:
| Env Variable | Config Key | Description |
|-------------|-----------|----------|
| `DB_HOST` | `db-host` | Database host |
| `DB_PORT` | `db-port` | Database port |
| `DB_USER` | `db-user` | Database user |
| `DB_PASSWORD` | `db-password` | Database password |
| `DB_NAME` | `db-name` | Database name |
| `CPW_PATCH_PATH` | `patch-path` | Base path for files |

---

## CLI Commands

### Review

```bash
$ ./bin/cpw
Usage:
	./cpw install           	Install updater: database setup, RSA keys generation, paths
	./cpw rsagen            	Regenerate RSA keys
	./cpw x [executable]    	Patch executable with public RSA key
	./cpw initial           	Creates initial (base) revision state
	./cpw new               	Creates the next revision, packs files and generates manifests
	./cpw listgen           	Regenerate files.md5 and incremental patches from current DB state
```

### Detailed description

#### `./cpw install` - System initialization

```bash
# Interactive installation
./cpw install

# Skip key generation (if already present)
./cpw install --skip-keys

# Skip database initialization (if already configured)
./cpw install --skip-db

# Preview without changes
./cpw install --help
```

**What it does:**
1. Creates the directory structure: `files/new/` and `files/CPW/`
2. Initializes `version` files with the value set in `min-*-ver`
3. (Optional) Creates database tables using `install_*.sql`
4. (Optional) Generates RSA keys and saves them to `keys.json`

---

#### `./cpw rsagen` - Generating RSA keys

```bash
# Standard generation
./cpw rsagen
```

**What it does:**
1. Generates an RSA-1024 key pair
2. Saves it to `config/keys.json` (atomically, with a backup)
3. Outputs the public key for copying

**Output Format:**
```
Generated Public Key:
────────────────────────────────────────────────────
# RSA Public Key (copy-paste ready)
# Modulus (hex): a1b2c3...
# Exponent: 65537

-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
-----END PUBLIC KEY-----
────────────────────────────────────────────────────

Keys saved to config/keys.json
Tip: Set file permissions to 600 for security: chmod 600 config/keys.json
```

---

#### `./cpw x [executable]` - Injecting the key into the binary

```bash
# Patching an executable file
./cpw x client/Launcher.exe

# With a custom marker (if different from the default)
./cpw x client/Launcher.exe --marker="__CUSTOM_MARKER__"

# A preview of what will be done
./cpw x client/Launcher.exe --help
```

**Client Requirements:**
The client source code must include a placeholder token of sufficient size.

**What it does:**
1. Locates the token in the binary (via byte pattern search)
2. Replaces it with the serialized public key (format: 4 Base64 strings)
3. Preserves the original file size (via zero-padding)
4. Verifies the write operation

---

#### `./cpw initial` - Preparing a basic audit

```bash
# Standard launch
./cpw initial

# Preview
./cpw initial --help
```

**What it does:**
1. Creates the directory structure: `files/new/{element,launcher,patcher}/`
2. Creates the `files/CPW/{type}/{type}/` directory structure for packaged files
3. Initializes `version` files with the value set in `min-*-ver` (defaults to 1)
4. Synchronizes the state with the database
5. Creates `/info/pid` with default value 101

**Attention**: delete all `*.sw` files on the original client in the `/config/(element, launcher, patcher)` folder

---

#### `./cpw new` - Creating the next revision

```bash
# Standard launch
./cpw new

# Skip manifest generation (packaging + DB only)
./cpw new --skip-manifests

# Forced overwrite (crash recovery)
./cpw new --force

# Preview
./cpw new --help
```

**What it does:**
1. Reads files from `files/new/{type}/` (recursively)
2. Compresses each file using the format: `[4-byte LE size][deflate(data, level=1)]`
3. Renames the files to Base64 (e.g., `data/config.ini` becomes `ZGF0YV9jb25maWcuaW5p`)
4. Calculates the MD5 checksum of the **compressed** file
5. Writes metadata to the database (via UPSERT)
6. Automatically generates manifests (`files.md5`, `v-N.inc`, along with the RSA signature)
7. Updates the `version` files

**Result:**
```
Revision published successfully!

New revision state:
  element:   v2
  launcher:  v2
  patcher:   v2

Clients can now update to this revision.
```

**Note**: Ready-made update files can be obtained from the original `Launcher` if `/patcher/server/updateserver.txt` contains a link to an open source with files

---

#### `./cpw listgen` - Regeneration of manifestos

```bash
# Complete regeneration of all types
./cpw listgen

# Only for specific type
./cpw listgen --type=element

# Preview
./cpw listgen --help
```

**What it does:**
1. Reads the **current** revision state from the database
2. Generates `files.md5`:
   ```
   # 2
   abc123... data/Y29uZmlnLmluaQ    # first entry in the folder
   def456... Y29uZmlnLmluaQ         # the rest are in the same folder
   ```
3. Signs the manifest using MD5withRSA
4. Generates incremental patches (`v-N.inc`) with the following prefixes:
    - `+` - File added within this revision range
    - `!` - File modified within this range
5. Updates the `version` files

**When to use:**
- Accidentally deleted or corrupted `files.md5` or `v-N.inc`
- After manually modifying database records
- For auditing purposes: to regenerate manifests from the current database state

---

## Examples of use

### Full workflow (first run)

```bash
# 1. System Initialization
./cpw install
# Prompts for database credentials, generates keys, and creates directory structure

# 2. Preparing Source Files
cp -r ~/game-client/element/* files/new/element/
cp -r ~/game-client/launcher/* files/new/launcher/

# 3. Creating the First Revision
./cpw new
# Packs files, writes metadata to the DB, and generates manifests

# 4. Patching the Client Binaries (Done once during build)
./cpw x client/launcher.exe
./cpw x client/patcher.exe

# 5. Distribution: Files inside files/CPW/ are ready for client download
```

### Adding an update

```bash
# 1. We put new/modified files
cp new_feature.data files/new/element/data/

# 2. Create a new revision
./cpw new
# Automatic: packaging, database, revision +1, manifests

# 3. Synchronize with the distribution server
rsync -av files/CPW/ cdn-server:/var/www/patch/
```

### Disaster recovery

```bash
# If the disk is full or the manifests are corrupted

# 1. Checking the database status
mysql -u user -p password -e "SELECT MAX(revision) FROM files WHERE type='element';"

# 2. Regenerating manifests from the database
./cpw listgen

# 3. Checking the integrity
./cpw listgen --help
```

### Running in Docker

Example using Docker. The following services are considered: pw-db, pw-web, and pw-server. pw-web includes CPW and the web pwadmin.

```yaml
# docker-compose.yml
services:
  pw-db:
    image: mariadb:10.6
    container_name: pw-db
    restart: unless-stopped
    env_file: .env
    environment:
      MARIADB_DATABASE: ${DB_NAME}
      MARIADB_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MARIADB_USER: ${DB_USER}
      MARIADB_PASSWORD: ${DB_PASSWORD}
    command: [
      "--sql-mode=", 
      "--lower-case-table-names=1",
      "--character-set-server=latin1",
      "--collation-server=latin1_swedish_ci",
      "--innodb-buffer-pool-size=512M",
      "--max-connections=500"
    ]
    volumes:
      - db_data:/var/lib/mysql
      - ./sql:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 5s
      timeout: 5s
      retries: 5
      start_period: 20s
    networks:
      - pw-net

  pw-web:
    build:
      context: .
      dockerfile: Dockerfile.web
    container_name: pw-web
    restart: unless-stopped
    environment:
      PW_SERVER_HOST: pw-server
      DB_HOST: pw-db
      DB_NAME: ${DB_NAME}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ./etc:/etc
      - ./patcher:/opt/pw/patcher 
      - ./patcher/files/CPW:/var/www/html/autopatcher:ro
      - ./pwadmin:/var/www/html/pwadmin
    ports:
      - "80:80"
    depends_on:
      pw-db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - pw-net
  
networks:
  pw-net:
    driver: bridge

volumes:
  db_data:
```

```bash
# Launch
docker-compose up -d

# Viewing logs
docker-compose logs -f pw-web

# Executing a command in a container
docker-compose exec pw-web /opt/pw/patcher/cpw listgen
```

---

## Docker

### Build the image

Nginx to transfer finished files to the client.

```dockerfile
# Dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ARG BASE_URL="https://github.com/MrBIOSs/cpw_pw/releases/latest/download"

RUN curl -L -s "${BASE_URL}/cpw" -o ./cpw \
    && curl -L -s "${BASE_URL}/cpw.sha256" -o ./cpw.sha256 \
    && sha256sum -c cpw.sha256 \
    && chmod +x ./cpw \
    && rm cpw.sha256

COPY config/ ./config/

RUN useradd -m -u 1000 patcher && chown -R patcher:patcher /app
USER patcher

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ./cpw || exit 1

CMD ["sh", "-c", "nginx -g 'daemon off;' & exec /app/bin/server"]
```

```bash
docker build -t pw-web .
```
and

```bash
docker exec -it pw-web ./cpw
```

---

## Safety

### File access rights

```bash
# After generating the keys
chmod 600 config/keys.json
chown patcher:patcher config/keys.json

# For logs
chmod 750 log/
chown -R patcher:patcher log/
```

### Auditing and logging

- Private keys are **never** logged.

### Updating dependencies

```bash
# Vulnerability check
dart pub outdated --mode=null-safety
dart pub deps --style=compact

# Update
dart pub upgrade --major-versions
dart pub get

# Reanalysis
dart analyze
dart test
```

---

## Troubleshooting

### "Marker not found in executable"

**Cause**: The `-----BEGIN PUBLIC KEY-----` placeholder token was not found in the binary.

**Solution**:
1. Ensure the token exists in the client's source code.
2. Try specifying a custom token: `./cpw x client.exe --marker="__MARKER__"`

### "Database connection failed"

**Cause**: Failed to connect to the database.

**Diagnostics**:
```bash
# Access check
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD -e "SELECT 1;"

# Permissions check
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "SHOW TABLES;"
```

**Solution**:
- Make sure the database is running and accessible over the network
- Check the connection parameters in `patcher.conf` or env vars
- Make sure the user has `CREATE TABLE`, `INSERT`, and `SELECT` permissions

### "Serialized key exceeds placeholder size"

**Cause**: The serialized public key (216 bytes Base64 + 3 `\n` = 219 bytes) does not fit into the token.

### "Version file out of sync"

**Cause**: The `version` file was manually modified and does not match the database.

**Solution**:
- The system will automatically fix the desync the next time you run `new` or `listgen`
- If you need to force a revision change: delete records with `revision > N` in the DB, then run `./cpw listgen`

### Logs for debugging

```bash
# View recent errors
tail -f log/errors.log
```

---

## Migrating from Java

### Transferring keys

If keys are stored in patcher.conf:
1. Run `./cpw rsagen` to generate new keys
2. Manually change the data in `keys.json`

---

## License

MIT License - see [LICENSE](LICENSE) file.

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes + add tests
4. Ensure all checks pass: `dart analyze && dart test`
5. Submit a pull request

---

## Support

- Bugs: [GitHub Issues](https://github.com/MrBIOSs/cpw_pw/issues)
- Email: nikolausgorkun@gmail.com

---