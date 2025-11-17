# Phase 3 Example: Template Strings
# Demonstrates JavaScript-style template literals

# Basic template string
NAME = "World"
greeting = `Hello, ${NAME}!`
echo {greeting}

# Multiple interpolations
USER = "admin"
HOST = "server.example.com"
PORT = 22
connection_string = `ssh ${USER}@${HOST} -p ${PORT}`
echo Connection: {connection_string}

# Expressions in templates
X = 10
Y = 20
result = `The sum of ${X} and ${Y} is ${X + Y}`
echo {result}

# Complex expressions
ITEMS = ["apple", "banana", "orange"]
COUNT = 3
message = `You have ${COUNT} items: ${ITEMS[0]}, ${ITEMS[1]}, ${ITEMS[2]}`
echo {message}

# Templates with shell()
DIR = "/var/log"
PATTERN = "error"
search_cmd = `grep -r "${PATTERN}" ${DIR}`
result = shell(search_cmd)
if (result.success) {
    echo Found errors in logs
}

# Building SQL queries
TABLE = "users"
FIELD = "email"
VALUE = "user@example.com"
query = `SELECT * FROM ${TABLE} WHERE ${FIELD} = '${VALUE}'`
echo Query: {query}

# Multi-line templates (future feature)
# config = `
# server {
#     listen ${PORT};
#     server_name ${DOMAIN};
#     root ${WEB_ROOT};
# }
# `

# Nested templates
PROTOCOL = "https"
DOMAIN = "api.example.com"
VERSION = "v2"
ENDPOINT = "users"
url = `${PROTOCOL}://${DOMAIN}/${VERSION}/${ENDPOINT}`
full_command = `curl -X GET "${url}" -H "Authorization: Bearer ${TOKEN}"`