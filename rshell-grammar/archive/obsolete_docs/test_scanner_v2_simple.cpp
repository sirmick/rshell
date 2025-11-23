/**
 * Simple Scanner V2 Tests
 *
 * Basic tests without Google Test dependency.
 */

#include "../src/scanner.h"
#include <iostream>
#include <cassert>
#include <cstring>

using namespace rshell;

// Test counter
int tests_passed = 0;
int tests_failed = 0;

#define TEST(name) \
  void test_##name(); \
  struct TestRegistrar_##name { \
    TestRegistrar_##name() { \
      std::cout << "Running: " << #name << "... "; \
      try { \
        test_##name(); \
        tests_passed++; \
        std::cout << "✓ PASS\n"; \
      } catch (const char* msg) { \
        tests_failed++; \
        std::cout << "✗ FAIL: " << msg << "\n"; \
      } \
    } \
  } test_registrar_##name; \
  void test_##name()

#define ASSERT_TRUE(expr) \
  if (!(expr)) throw "Assertion failed: " #expr

#define ASSERT_FALSE(expr) \
  if (expr) throw "Assertion failed: NOT " #expr

#define ASSERT_EQ(a, b) \
  if ((a) != (b)) throw "Assertion failed: " #a " == " #b

// ===== Pattern Matching Tests =====

TEST(keyword_detection) {
  Scanner scanner;
  
  ASSERT_TRUE(scanner.is_keyword("if"));
  ASSERT_TRUE(scanner.is_keyword("for"));
  ASSERT_TRUE(scanner.is_keyword("while"));
  ASSERT_TRUE(scanner.is_keyword("return"));
  ASSERT_TRUE(scanner.is_keyword("break"));
  ASSERT_TRUE(scanner.is_keyword("continue"));
  ASSERT_TRUE(scanner.is_keyword("else"));
  
  ASSERT_FALSE(scanner.is_keyword("echo"));
  ASSERT_FALSE(scanner.is_keyword("ls"));
  ASSERT_FALSE(scanner.is_keyword("ifnot"));
  ASSERT_FALSE(scanner.is_keyword(""));
}

TEST(assignment_detection) {
  Scanner scanner;
  
  ASSERT_TRUE(scanner.is_assignment("X="));
  ASSERT_TRUE(scanner.is_assignment("X ="));
  ASSERT_TRUE(scanner.is_assignment("X  ="));
  ASSERT_TRUE(scanner.is_assignment("COUNT="));
  ASSERT_TRUE(scanner.is_assignment("X+="));
  ASSERT_TRUE(scanner.is_assignment("X-="));
  ASSERT_TRUE(scanner.is_assignment("X*="));
  ASSERT_TRUE(scanner.is_assignment("X/="));
  ASSERT_TRUE(scanner.is_assignment("X%="));
  
  ASSERT_FALSE(scanner.is_assignment("echo"));
  ASSERT_FALSE(scanner.is_assignment("ls -la"));
  ASSERT_FALSE(scanner.is_assignment(""));
  ASSERT_FALSE(scanner.is_assignment("123"));
}

// ===== Serialization Tests =====

TEST(serialization_round_trip) {
  Scanner scanner1;
  
  // Set up state
  scanner1.state().current_mode = Mode::Expr;
  scanner1.state().at_line_start = false;
  scanner1.state().expr_block_depth = 2;
  scanner1.state().cmd_paren_depth = 1;
  scanner1.state().expr_interp_depth = 3;
  
  // Serialize
  auto buffer = scanner1.serialize();
  ASSERT_TRUE(buffer.size() > 0);
  
  // Deserialize
  Scanner scanner2;
  scanner2.deserialize(buffer.data(), buffer.size());
  
  // Verify
  ASSERT_EQ(scanner2.state().current_mode, Mode::Expr);
  ASSERT_EQ(scanner2.state().at_line_start, false);
  ASSERT_EQ(scanner2.state().expr_block_depth, 2);
  ASSERT_EQ(scanner2.state().cmd_paren_depth, 1);
  ASSERT_EQ(scanner2.state().expr_interp_depth, 3);
}

TEST(serialization_default_state) {
  Scanner scanner1;
  
  // Serialize default state
  auto buffer = scanner1.serialize();
  
  // Deserialize
  Scanner scanner2;
  scanner2.deserialize(buffer.data(), buffer.size());
  
  // Verify defaults
  ASSERT_EQ(scanner2.state().current_mode, Mode::Uninit);
  ASSERT_EQ(scanner2.state().at_line_start, true);
  ASSERT_EQ(scanner2.state().expr_block_depth, 0);
  ASSERT_EQ(scanner2.state().cmd_paren_depth, 0);
  ASSERT_EQ(scanner2.state().expr_interp_depth, 0);
}

TEST(serialization_empty_buffer) {
  Scanner scanner;
  scanner.deserialize(nullptr, 0);
  
  // Should have default state
  ASSERT_EQ(scanner.state().current_mode, Mode::Uninit);
  ASSERT_EQ(scanner.state().expr_block_depth, 0);
}

// ===== State Tests =====

TEST(initial_state) {
  Scanner scanner;
  
  ASSERT_EQ(scanner.state().current_mode, Mode::Uninit);
  ASSERT_EQ(scanner.state().at_line_start, true);
  ASSERT_EQ(scanner.state().expr_block_depth, 0);
  ASSERT_EQ(scanner.state().cmd_paren_depth, 0);
  ASSERT_EQ(scanner.state().expr_interp_depth, 0);
}

TEST(mode_transitions) {
  Scanner scanner;
  
  ASSERT_EQ(scanner.state().current_mode, Mode::Uninit);
  
  scanner.state().current_mode = Mode::Expr;
  ASSERT_EQ(scanner.state().current_mode, Mode::Expr);
  
  scanner.state().current_mode = Mode::Cmd;
  ASSERT_EQ(scanner.state().current_mode, Mode::Cmd);
}

// ===== Delimiter Tracking Tests =====

TEST(expr_block_depth_tracking) {
  Scanner scanner;
  
  // Initial state
  ASSERT_EQ(scanner.state().expr_block_depth, 0);
  
  // Increment depth
  scanner.state().expr_block_depth++;
  ASSERT_EQ(scanner.state().expr_block_depth, 1);
  
  scanner.state().expr_block_depth++;
  ASSERT_EQ(scanner.state().expr_block_depth, 2);
  
  // Decrement depth
  scanner.state().expr_block_depth--;
  ASSERT_EQ(scanner.state().expr_block_depth, 1);
  
  scanner.state().expr_block_depth--;
  ASSERT_EQ(scanner.state().expr_block_depth, 0);
}

TEST(cmd_paren_depth_tracking) {
  Scanner scanner;
  
  // Initial state
  ASSERT_EQ(scanner.state().cmd_paren_depth, 0);
  ASSERT_EQ(scanner.state().in_rsh_call, false);
  
  // Start $rsh() call
  scanner.state().in_rsh_call = true;
  scanner.state().cmd_paren_depth = 1;
  
  ASSERT_EQ(scanner.state().in_rsh_call, true);
  ASSERT_EQ(scanner.state().cmd_paren_depth, 1);
  
  // Nested parens in $rsh()
  scanner.state().cmd_paren_depth++;
  ASSERT_EQ(scanner.state().cmd_paren_depth, 2);
  
  // Close nested paren
  scanner.state().cmd_paren_depth--;
  ASSERT_EQ(scanner.state().cmd_paren_depth, 1);
  ASSERT_EQ(scanner.state().in_rsh_call, true);
  
  // Close $rsh()
  scanner.state().cmd_paren_depth--;
  scanner.state().in_rsh_call = false;
  ASSERT_EQ(scanner.state().cmd_paren_depth, 0);
  ASSERT_EQ(scanner.state().in_rsh_call, false);
}

TEST(expr_interp_depth_tracking) {
  Scanner scanner;
  
  // Initial state
  ASSERT_EQ(scanner.state().expr_interp_depth, 0);
  ASSERT_EQ(scanner.state().in_expr_interp, false);
  
  // Start ${} interpolation
  scanner.state().in_expr_interp = true;
  scanner.state().expr_interp_depth = 1;
  
  ASSERT_EQ(scanner.state().in_expr_interp, true);
  ASSERT_EQ(scanner.state().expr_interp_depth, 1);
  
  // Nested braces in ${}
  scanner.state().expr_interp_depth++;
  ASSERT_EQ(scanner.state().expr_interp_depth, 2);
  
  // Close nested brace
  scanner.state().expr_interp_depth--;
  ASSERT_EQ(scanner.state().expr_interp_depth, 1);
  ASSERT_EQ(scanner.state().in_expr_interp, true);
  
  // Close ${}
  scanner.state().expr_interp_depth--;
  scanner.state().in_expr_interp = false;
  ASSERT_EQ(scanner.state().expr_interp_depth, 0);
  ASSERT_EQ(scanner.state().in_expr_interp, false);
}

TEST(delimiter_tracking_serialization) {
  Scanner scanner1;
  
  // Set up complex delimiter state
  scanner1.state().current_mode = Mode::Expr;
  scanner1.state().expr_block_depth = 2;
  scanner1.state().cmd_paren_depth = 1;
  scanner1.state().expr_interp_depth = 3;
  scanner1.state().in_rsh_call = true;
  scanner1.state().in_expr_interp = true;
  
  // Serialize
  auto buffer = scanner1.serialize();
  
  // Deserialize
  Scanner scanner2;
  scanner2.deserialize(buffer.data(), buffer.size());
  
  // Verify all delimiter state preserved
  ASSERT_EQ(scanner2.state().expr_block_depth, 2);
  ASSERT_EQ(scanner2.state().cmd_paren_depth, 1);
  ASSERT_EQ(scanner2.state().expr_interp_depth, 3);
  ASSERT_EQ(scanner2.state().in_rsh_call, true);
  ASSERT_EQ(scanner2.state().in_expr_interp, true);
}

TEST(function_call_detection) {
  Scanner scanner;
  
  // Simple function calls
  ASSERT_TRUE(scanner.is_function_call("print()"));
  ASSERT_TRUE(scanner.is_function_call("print(\"hello\")"));
  ASSERT_TRUE(scanner.is_function_call("log.write()"));
  ASSERT_TRUE(scanner.is_function_call("obj.method()"));
  
  // With whitespace
  ASSERT_TRUE(scanner.is_function_call("  print()"));
  ASSERT_TRUE(scanner.is_function_call("print  ()"));
  
  // Chained calls
  ASSERT_TRUE(scanner.is_function_call("obj.method.call()"));
  // TODO: Array indexing with method calls needs more complex parsing
  // ASSERT_TRUE(scanner.is_function_call("items[0].process()"));
  ASSERT_TRUE(scanner.is_function_call("server.api.call()"));
  
  // Not function calls
  ASSERT_FALSE(scanner.is_function_call("echo"));
  ASSERT_FALSE(scanner.is_function_call("ls -la"));
  ASSERT_FALSE(scanner.is_function_call("X = 42"));
  ASSERT_FALSE(scanner.is_function_call(""));
}

TEST(compound_assignment_detection) {
  Scanner scanner;
  
  // All compound assignment operators
  ASSERT_TRUE(scanner.is_assignment("X+=1"));
  ASSERT_TRUE(scanner.is_assignment("X-=5"));
  ASSERT_TRUE(scanner.is_assignment("X*=2"));
  ASSERT_TRUE(scanner.is_assignment("X/=10"));
  ASSERT_TRUE(scanner.is_assignment("X%=3"));
  
  // With whitespace
  ASSERT_TRUE(scanner.is_assignment("X += 1"));
  ASSERT_TRUE(scanner.is_assignment("COUNT  +=  10"));
  
  // Regular assignment (already tested, but critical)
  ASSERT_TRUE(scanner.is_assignment("X=42"));
  ASSERT_TRUE(scanner.is_assignment("X = 42"));
}

// ===== Main =====

int main() {
  std::cout << "\n===== RShell Scanner V2 - Simple Tests =====\n\n";
  
  // Tests run automatically via static initializers
  
  std::cout << "\n===== Test Summary =====\n";
  std::cout << "Passed: " << tests_passed << "\n";
  std::cout << "Failed: " << tests_failed << "\n";
  std::cout << "Total:  " << (tests_passed + tests_failed) << "\n";
  
  if (tests_failed == 0) {
    std::cout << "\n✓ All tests passed!\n\n";
    return 0;
  } else {
    std::cout << "\n✗ Some tests failed\n\n";
    return 1;
  }
}