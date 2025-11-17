#!/usr/bin/env rshell
# Example 6: Data Processing Pipeline with Functions
# Demonstrates: Function definitions, higher-order functions, data transformation

# Define reusable functions

# Function to validate email addresses
validate_email = function(email) {
  if (email.contains('@') and email.contains('.')) {
    parts = email.split('@')
    if (parts.length == 2 and parts[1].contains('.')) {
      return true
    }
  }
  return false
}

# Function to normalize user data
normalize_user = function(user) {
  normalized = {
    'id': user.id,
    'name': user.name.trim().title_case(),
    'email': user.email.lower(),
    'created_at': user.created_at,
    'active': user.active or false
  }
  return normalized
}

# Function to calculate user score
calculate_score = function(user, orders) {
  # Base score from account age
  created = user.created_at.to_timestamp()
  now = shell(date +%s).stdout.trim().to_int()
  age_days = (now - created) / (24 * 60 * 60)
  age_score = age_days.min(365) / 365 * 100
  
  # Score from orders
  order_count = orders.length
  order_score = order_count.min(50) * 2
  
  # Total score
  total = (age_score + order_score) / 2
  
  return {
    'total': total.round(2),
    'age_score': age_score.round(2),
    'order_score': order_score
  }
}

# Function to generate report section
generate_section = function(title, data, format) {
  output = '\n=== ' + title + ' ===\n'
  
  if (format == 'table') {
    for item in data {
      output = output + '  ' + item.name + ': ' + item.value + '\n'
    }
  } elif (format == 'list') {
    for item in data {
      output = output + '  - ' + item + '\n'
    }
  } elif (format == 'json') {
    output = output + data.to_json() + '\n'
  }
  
  return output
}

# Function to filter by predicate
filter_by = function(items, predicate) {
  result = []
  for item in items {
    if (predicate(item)) {
      result += item
    }
  }
  return result
}

# Function to map/transform items
map_transform = function(items, transformer) {
  result = []
  for item in items {
    result += transformer(item)
  }
  return result
}

# Function to reduce/aggregate
reduce_sum = function(items, key) {
  total = 0
  for item in items {
    if (key) {
      total += item[key]
    } else {
      total += item
    }
  }
  return total
}

echo === Data Processing Pipeline ===
echo
echo Loading data...

# Load user data (simulated - would normally read from file/API)
USERS = [
  {'id': 1, 'name': '  alice smith  ', 'email': 'ALICE@EXAMPLE.COM', 'created_at': 1609459200, 'active': true},
  {'id': 2, 'name': 'bob jones', 'email': 'bob@test.com', 'created_at': 1625097600, 'active': true},
  {'id': 3, 'name': 'charlie brown', 'email': 'invalid-email', 'created_at': 1640995200, 'active': false},
  {'id': 4, 'name': 'diana prince', 'email': 'diana@example.com', 'created_at': 1656633600, 'active': true}
]

# Load order data
ORDERS = [
  {'user_id': 1, 'total': 99.99, 'status': 'completed'},
  {'user_id': 1, 'total': 149.50, 'status': 'completed'},
  {'user_id': 1, 'total': 75.00, 'status': 'pending'},
  {'user_id': 2, 'total': 50.00, 'status': 'completed'},
  {'user_id': 2, 'total': 125.00, 'status': 'completed'},
  {'user_id': 4, 'total': 200.00, 'status': 'completed'}
]

echo Loaded {USERS.length} users and {ORDERS.length} orders
echo

# PIPELINE STEP 1: Validate and normalize users
echo Step 1: Validating and normalizing users...

VALIDATED_USERS = []
INVALID_USERS = []

for user in USERS {
  # Validate email
  if (validate_email(user.email)) {
    # Normalize user data
    normalized = normalize_user(user)
    VALIDATED_USERS += normalized
  } else {
    INVALID_USERS += user
    echo   ⚠ Invalid email for user {user.id}: {user.email}
  }
}

echo   ✓ Validated {VALIDATED_USERS.length} users
echo   ✗ Rejected {INVALID_USERS.length} users
echo

# PIPELINE STEP 2: Enrich users with order data
echo Step 2: Enriching users with order data...

ENRICHED_USERS = []

for user in VALIDATED_USERS {
  # Find user's orders
  user_orders = filter_by(ORDERS, function(order) {
    return order.user_id == user.id
  })
  
  # Calculate statistics
  completed_orders = filter_by(user_orders, function(order) {
    return order.status == 'completed'
  })
  
  total_spent = reduce_sum(completed_orders, 'total')
  
  # Calculate user score
  score_data = calculate_score(user, completed_orders)
  
  # Create enriched user object
  enriched = {
    'id': user.id,
    'name': user.name,
    'email': user.email,
    'active': user.active,
    'order_count': user_orders.length,
    'completed_orders': completed_orders.length,
    'total_spent': total_spent,
    'score': score_data.total,
    'score_breakdown': score_data
  }
  
  ENRICHED_USERS += enriched
}

echo   ✓ Enriched {ENRICHED_USERS.length} users
echo

# PIPELINE STEP 3: Segment users
echo Step 3: Segmenting users...

# Define segmentation predicates
is_vip = function(user) {
  return user.total_spent > 100 and user.completed_orders >= 2
}

is_active = function(user) {
  return user.active and user.order_count > 0
}

is_at_risk = function(user) {
  return user.active and user.order_count == 0
}

# Segment users
VIP_USERS = filter_by(ENRICHED_USERS, is_vip)
ACTIVE_USERS = filter_by(ENRICHED_USERS, is_active)
AT_RISK_USERS = filter_by(ENRICHED_USERS, is_at_risk)

echo   VIP users: {VIP_USERS.length}
echo   Active users: {ACTIVE_USERS.length}
echo   At-risk users: {AT_RISK_USERS.length}
echo

# PIPELINE STEP 4: Generate insights
echo Step 4: Generating insights...

INSIGHTS = {
  'total_users': ENRICHED_USERS.length,
  'total_revenue': reduce_sum(ENRICHED_USERS, 'total_spent'),
  'average_order_value': 0,
  'top_customers': [],
  'segments': {
    'vip': VIP_USERS.length,
    'active': ACTIVE_USERS.length,
    'at_risk': AT_RISK_USERS.length
  }
}

# Calculate average order value
completed_order_totals = map_transform(ORDERS, function(order) {
  if (order.status == 'completed') {
    return order.total
  }
  return 0
})
INSIGHTS.average_order_value = (reduce_sum(completed_order_totals, null) / completed_order_totals.length).round(2)

# Find top customers (by score)
sorted_users = ENRICHED_USERS.sort_by(function(user) {
  return -user.score  # Negative for descending
})
INSIGHTS.top_customers = sorted_users[0:3]

echo   ✓ Insights generated
echo

# PIPELINE STEP 5: Generate reports
echo Step 5: Generating reports...

# Console report
echo
echo ==========================================
echo DATA PIPELINE REPORT
echo ==========================================
echo

# Summary section
summary_data = [
  {'name': 'Total Users', 'value': INSIGHTS.total_users},
  {'name': 'Total Revenue', 'value': '$' + INSIGHTS.total_revenue.round(2)},
  {'name': 'Avg Order Value', 'value': '$' + INSIGHTS.average_order_value},
  {'name': 'VIP Customers', 'value': INSIGHTS.segments.vip},
  {'name': 'At-Risk Customers', 'value': INSIGHTS.segments.at_risk}
]

echo generate_section('Summary', summary_data, 'table')

# Top customers section
echo
echo === Top Customers (by Score) ===
RANK = 1
for user in INSIGHTS.top_customers {
  echo   {RANK}. {user.name} (score: {user.score})
  echo      Email: {user.email}
  echo      Orders: {user.completed_orders} | Spent: ${user.total_spent}
  echo
  RANK += 1
}

# Segment details
echo === VIP Customers ===
for user in VIP_USERS {
  echo   - {user.name}: {user.completed_orders} orders, ${user.total_spent} spent
}
echo

if (AT_RISK_USERS.length > 0) {
  echo === At-Risk Customers (No Orders) ===
  for user in AT_RISK_USERS {
    echo   ⚠ {user.name} ({user.email})
  }
  echo
}

# Generate JSON export
echo Exporting data...
EXPORT = {
  'generated_at': shell(date -Iseconds).stdout.trim(),
  'users': ENRICHED_USERS,
  'insights': INSIGHTS,
  'segments': {
    'vip': VIP_USERS,
    'active': ACTIVE_USERS,
    'at_risk': AT_RISK_USERS
  }
}

EXPORT_FILE = '/tmp/data_pipeline_export.json'
shell(echo {EXPORT.to_json()} > {EXPORT_FILE})
echo   ✓ Exported to {EXPORT_FILE}

# Generate CSV for VIP customers
echo
echo Generating VIP customer CSV...
CSV_FILE = '/tmp/vip_customers.csv'
CSV_HEADER = 'ID,Name,Email,Orders,Total Spent,Score\n'
CSV_ROWS = CSV_HEADER

for user in VIP_USERS {
  row = user.id + ',' + user.name + ',' + user.email + ',' + user.completed_orders + ',' + user.total_spent + ',' + user.score + '\n'
  CSV_ROWS = CSV_ROWS + row
}

shell(echo {CSV_ROWS} > {CSV_FILE})
echo   ✓ CSV saved to {CSV_FILE}

echo
echo ==========================================
echo Pipeline completed successfully!
echo ==========================================
echo
echo Next steps:
echo   1. Review VIP customers: cat {CSV_FILE}
echo   2. Analyze insights: cat {EXPORT_FILE}
echo   3. Contact at-risk customers
echo

exit 0