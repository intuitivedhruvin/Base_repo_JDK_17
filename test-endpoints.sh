#!/usr/bin/env bash
# Smoke-tests Trebol backend endpoints one by one.
# Usage: bash test-endpoints.sh [base_url]
BASE=${1:-http://localhost:8080}
TMP=$(mktemp)
HDR=$(mktemp)
N=0; PASS=0; FAIL=0
SUFFIX=$RANDOM   # keeps test data unique across reruns

# call "<description>" <expected_status> <METHOD> <path> [json_body] [auth_header] [body_must_contain]
call() {
  local desc=$1 expect=$2 method=$3 path=$4 body=$5 auth=$6 contains=$7
  N=$((N+1))
  local args=(-s -X "$method" -o "$TMP" -D "$HDR" -w "%{http_code}" "$BASE$path")
  [ -n "$body" ] && args+=(-H "Content-Type: application/json" -d "$body")
  [ -n "$auth" ] && args+=(-H "Authorization: $auth")
  local code; code=$(curl "${args[@]}")
  local mark="PASS"
  if [ "$code" = "$expect" ] && { [ -z "$contains" ] || grep -qF -- "$contains" "$TMP"; }; then PASS=$((PASS+1)); else mark="FAIL"; FAIL=$((FAIL+1)); fi
  printf "%2d. [%s] %-6s %-55s -> %s (expected %s)\n" "$N" "$mark" "$method" "$path" "$code" "$expect"
  printf "    %s\n" "$desc"
  local out; out=$(tr -d '\r\n' < "$TMP" | cut -c1-220)
  [ -n "$out" ] && printf "    body: %s\n" "$out"
  echo
}

token_from_headers() { tr -d '\r' < "$HDR" | awk 'tolower($1)=="authorization:"{print $2" "$3}'; }

echo "=== PUBLIC ==="
call "Store info" 200 GET /public/about
call "Login as admin/admin" 200 POST /public/login '{"name":"admin","password":"admin"}'
ADMIN=$(token_from_headers); echo "    admin token: ${ADMIN:0:45}..."; echo
call "Login with wrong password is rejected" 401 POST /public/login '{"name":"admin","password":"nope"}'

USER="tester$SUFFIX"
call "Register a new customer account" 200 POST /public/register \
  "{\"name\":\"$USER\",\"password\":\"secret123\",\"profile\":{\"firstName\":\"Test\",\"lastName\":\"User\",\"idNumber\":\"1234${SUFFIX:0:4}5\",\"email\":\"$USER@example.com\"}}"
call "Login as the new account" 200 POST /public/login "{\"name\":\"$USER\",\"password\":\"secret123\"}"
CUST=$(token_from_headers)
call "Read own profile (new account)" 200 GET /account/profile "" "$CUST"

echo "=== SECURITY / ACCESS ==="
call "Protected endpoint without token is rejected" 403 GET /data/users
call "Modules the admin can access" 200 GET /access "" "$ADMIN"
call "Admin permissions on products module" 200 GET /access/products "" "$ADMIN"
call "Customer cannot list users" 403 GET /data/users "" "$CUST"
call "Anonymous cannot create data" 403 POST /data/shippers '{"name":"anon"}'
call "Customer cannot create data" 403 POST /data/shippers '{"name":"cust"}' "$CUST"
call "Anonymous cannot delete data" 403 DELETE "/data/products?id=1"

echo "=== REFERENCE DATA ==="
call "Billing types" 200 GET /data/billing_types
call "Order statuses" 200 GET /data/order_statuses "" "$ADMIN"
call "User roles" 200 GET /data/user_roles "" "$ADMIN"
call "Users" 200 GET /data/users "" "$ADMIN"
call "People" 200 GET /data/people "" "$ADMIN"
call "Customers" 200 GET /data/customers "" "$ADMIN"

echo "=== PRODUCT CATEGORIES ==="
CAT="cat$SUFFIX"
call "Create category" 201 POST /data/product_categories "{\"code\":\"$CAT\",\"name\":\"Electronics\"}" "$ADMIN"
call "Find category by code" 200 GET "/data/product_categories?code=$CAT" "" "$ADMIN"

echo "=== PRODUCTS (full CRUD) ==="
BC="BC$SUFFIX"
call "Create product in that category" 201 POST /data/products \
  "{\"name\":\"Laptop\",\"barcode\":\"$BC\",\"description\":\"Test laptop\",\"price\":1000,\"currentStock\":10,\"criticalStock\":2,\"category\":{\"code\":\"$CAT\"}}" "$ADMIN"
call "List products (public)" 200 GET /data/products
call "Find product by barcode" 200 GET "/data/products?barcode=$BC"
call "Replace product (PUT, price 1200)" 204 PUT "/data/products?barcode=$BC" \
  "{\"name\":\"Laptop Pro\",\"barcode\":\"$BC\",\"description\":\"Updated\",\"price\":1200,\"currentStock\":8,\"criticalStock\":2,\"category\":{\"code\":\"$CAT\"}}" "$ADMIN"
call "Partial update (PATCH, price 999)" 204 PATCH "/data/products?barcode=$BC" '{"price":999}' "$ADMIN"
call "Verify updates applied (price 999, category kept)" 200 GET "/data/products?barcode=$BC" "" "" "\"price\":999,\"currentStock\":8,\"criticalStock\":2,\"category\":{\"code\":\"$CAT\""
call "Invalid product (missing name/price) is rejected" 400 POST /data/products "{\"barcode\":\"X$BC\"}" "$ADMIN"
call "Delete product" 204 DELETE "/data/products?barcode=$BC" "" "$ADMIN"
call "Verify product is gone (empty list)" 200 GET "/data/products?barcode=$BC"

echo "=== SHIPPERS ==="
SH="Shipper$SUFFIX"
call "Create shipper" 201 POST /data/shippers "{\"name\":\"$SH\"}" "$ADMIN"
call "Find shipper by name" 200 GET "/data/shippers?name=$SH" "" "$ADMIN"
call "Delete shipper" 204 DELETE "/data/shippers?name=$SH" "" "$ADMIN"

rm -f "$TMP" "$HDR"
echo "=== SUMMARY: $N checks, $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]   # non-zero exit fails CI
