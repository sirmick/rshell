# Phase 3 Example: shell() function
# Demonstrates running commands from expression mode

# Basic shell() usage
result = shell("ls -la")
if (result.success) {
    echo Files listed successfully
    echo Output lines: {result.stdout}
}

# Check if file exists
if (shell("test -f config.json").success) {
    echo Config file exists
    config = shell("cat config.json").stdout
}

# Using variables in shell()
CMD = "ps aux | grep node"
processes = shell(CMD)
echo Node processes: {processes.stdout}

# Template strings in shell()
DIR = "/tmp"
USER = "admin"
files = shell(`ls -l ${DIR} | grep ${USER}`)

# Loop with shell() calls
SERVERS = ["web1.example.com", "web2.example.com", "db.example.com"]
for SERVER in SERVERS {
    ping_result = shell(`ping -c 1 ${SERVER}`)
    if (ping_result.success) {
        echo {SERVER} is reachable
    } else {
        echo WARNING: {SERVER} is not responding
    }
}

# Chaining commands based on results
build = shell("make build")
if (build.success) {
    test = shell("make test")
    if (test.success) {
        deploy = shell("make deploy")
        echo Deployment status: {deploy.exit_code}
    }
}