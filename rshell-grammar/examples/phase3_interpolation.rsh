# Phase 3 Example: Command Interpolation with {}
# Demonstrates expression interpolation in command mode

# Simple variable interpolation
USER = "alice"
HOME = "/home/alice"
echo Welcome {USER} to {HOME}

# Property access
SERVER = {"host": "api.example.com", "port": 8443, "protocol": "https"}
curl {SERVER.protocol}://{SERVER.host}:{SERVER.port}/status

# Arithmetic expressions
COUNT = 42
LIMIT = 100
echo Processing {COUNT} of {LIMIT} items ({COUNT * 100 / LIMIT}% complete)

# List access
DIRS = ["/var/log", "/tmp", "/home"]
echo Checking directory {DIRS[0]}

# Complex expressions with conditionals
DEBUG = true
LOG_LEVEL = 3
echo Debug mode: {DEBUG and LOG_LEVEL > 2}

# Multiple interpolations in one command
NAME = "Bob"
AGE = 30
CITY = "New York"
echo User {NAME} is {AGE} years old and lives in {CITY}

# Path interpolation
SCRIPT_DIR = "./scripts"
SCRIPT_NAME = "deploy.sh"
{SCRIPT_DIR}/{SCRIPT_NAME} --environment production

# Using with loops
USERS = ["alice", "bob", "charlie"]
for USER in USERS {
    echo Creating home directory for {USER}
    mkdir -p /home/{USER}
    chown {USER}:{USER} /home/{USER}
}

# Nested property access
CONFIG = {
    "database": {
        "host": "db.example.com",
        "port": 5432,
        "name": "myapp"
    }
}
psql -h {CONFIG.database.host} -p {CONFIG.database.port} -d {CONFIG.database.name}

# Dynamic command construction
ACTION = "start"
SERVICE = "nginx"
systemctl {ACTION} {SERVICE}