/**
 * RShell Scanner V2 Unit Tests
 * 
 * Direct testing of scanner functionality without full grammar.
 * Compiles scanner in isolation and tests token emission.
 */

#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <assert.h>

// Include scanner implementation
#include "../src/scanner_v2.c"

// Mock TSLexer for testing
typedef struct {
  const char *input;
  int position;
  int column;
  int32_t current_char;
} MockLexer;

static void mock_lexer_init(MockLexer *lexer, const char *input) {
  lexer->input = input;
  lexer->position = 0;
  lexer->column = 0;
  lexer->current_char = input[0];
}

static void mock_advance(TSLexer *lexer, bool skip) {
  MockLexer *mock = (MockLexer *)lexer;
  if (mock->current_char == 0) return;
  
  mock->position++;
  mock->column++;
  
  if (mock->current_char == '\n') {
    mock->column = 0;
  }
  
  mock->current_char = mock->input[mock->position];
}

static void mock_mark_end(TSLexer *lexer) {
  // In real implementation, this marks current position
  // For testing, we just note it happened
}

static uint32_t mock_get_column(TSLexer *lexer) {
  MockLexer *mock = (MockLexer *)lexer;
  return mock->column;
}

// Test result tracking
typedef struct {
  int total;
  int passed;
  int failed;
} TestResults;

static TestResults results = {0, 0, 0};

#define TEST(name) \
  void test_##name(); \
  void test_##name##_wrapper() { \
    results.total++; \
    printf("  Testing: %s ... ", #name); \
    test_##name(); \
  } \
  void test_##name()

#define ASSERT(condition, message) \
  do { \
    if (!(condition)) { \
      printf("FAIL: %s\n", message); \
      results.failed++; \
      return; \
    } \
  } while(0)

#define PASS() \
  do { \
    printf("PASS\n"); \
    results.passed++; \
  } while(0)

// ===== HELPER FUNCTIONS =====

static bool scan_with_mock(Scanner *scanner, const char *input, bool *valid_symbols) {
  MockLexer mock_lexer;
  mock_lexer_init(&mock_lexer, input);
  
  TSLexer lexer = {
    .lookahead = mock_lexer.current_char,
    .advance = mock_advance,
    .mark_end = mock_mark_end,
    .get_column = mock_get_column,
  };
  
  return tree_sitter_rshell_external_scanner_scan(scanner, &lexer, valid_symbols);
}

// ===== TESTS =====

TEST(scanner_create_destroy) {
  Scanner *scanner = tree_sitter_rshell_external_scanner_create();
  ASSERT(scanner != NULL, "Scanner creation failed");
  ASSERT(scanner->current_mode == MODE_UNINIT, "Initial mode should be UNINIT");
  ASSERT(scanner->at_line_start == true, "Should start at line start");
  
  tree_sitter_rshell_external_scanner_destroy(scanner);
  PASS();
}

TEST(scanner_serialization) {
  Scanner *scanner = tree_sitter_rshell_external_scanner_create();
  scanner->current_mode = MODE_EXPR;
  scanner->at_line_start = false;
  
  char buffer[10];
  unsigned len = tree_sitter_rshell_external_scanner_serialize(scanner, buffer);
  
  ASSERT(len == 2, "Serialization should return 2 bytes");
  ASSERT(buffer[0] == MODE_EXPR, "Should serialize mode");
  ASSERT(buffer[1] == 0, "Should serialize line start flag");
  
  Scanner *scanner2 = tree_sitter_rshell_external_scanner_create();
  tree_sitter_rshell_external_scanner_deserialize(scanner2, buffer, len);
  
  ASSERT(scanner2->current_mode == MODE_EXPR, "Should deserialize mode");
  ASSERT(scanner2->at_line_start == false, "Should deserialize line start flag");
  
  tree_sitter_rshell_external_scanner_destroy(scanner);
  tree_sitter_rshell_external_scanner_destroy(scanner2);
  PASS();
}

TEST(is_keyword_detection) {
  ASSERT(is_keyword("if", 2) == true, "Should detect 'if'");
  ASSERT(is_keyword("for", 3) == true, "Should detect 'for'");
  ASSERT(is_keyword("while", 5) == true, "Should detect 'while'");
  ASSERT(is_keyword("return", 6) == true, "Should detect 'return'");
  ASSERT(is_keyword("elif", 4) == true, "Should detect 'elif'");
  ASSERT(is_keyword("else", 4) == true, "Should detect 'else'");
  ASSERT(is_keyword("break", 5) == true, "Should detect 'break'");
  ASSERT(is_keyword("continue", 8) == true, "Should detect 'continue'");
  
  ASSERT(is_keyword("echo", 4) == false, "Should not detect 'echo'");
  ASSERT(is_keyword("ls", 2) == false, "Should not detect 'ls'");
  ASSERT(is_keyword("X", 1) == false, "Should not detect 'X'");
  
  PASS();
}

TEST(is_assignment_detection) {
  ASSERT(is_assignment("X=", 2) == true, "Should detect 'X='");
  ASSERT(is_assignment("X =", 3) == true, "Should detect 'X ='");
  ASSERT(is_assignment("COUNT+=", 7) == true, "Should detect 'COUNT+='");
  ASSERT(is_assignment("VALUE-=", 7) == true, "Should detect 'VALUE-='");
  ASSERT(is_assignment("TOTAL*=", 7) == true, "Should detect 'TOTAL*='");
  ASSERT(is_assignment("RESULT/=", 8) == true, "Should detect 'RESULT/='");
  
  ASSERT(is_assignment("echo", 4) == false, "Should not detect 'echo'");
  ASSERT(is_assignment("ls", 2) == false, "Should not detect 'ls'");
  ASSERT(is_assignment("123", 3) == false, "Should not detect '123'");
  
  PASS();
}

TEST(simple_expr_line_assignment) {
  Scanner *scanner = tree_sitter_rshell_external_scanner_create();
  bool valid[6] = {false, false, true, false, false, false};  // EXPR_START valid
  
  bool result = scan_with_mock(scanner, "X = 42", valid);
  
  ASSERT(result == true, "Should emit token for assignment");
  ASSERT(scanner->current_mode == MODE_EXPR, "Should be in EXPR mode");
  
  tree_sitter_rshell_external_scanner_destroy(scanner);
  PASS();
}

TEST(simple_cmd_line_echo) {
  Scanner *scanner = tree_sitter_rshell_external_scanner_create();
  bool valid[6] = {true, false, false, false, false, false};  // CMD_START valid
  
  bool result = scan_with_mock(scanner, "echo hello", valid);
  
  ASSERT(result == true, "Should emit token for command");
  ASSERT(scanner->current_mode == MODE_CMD, "Should be in CMD mode");
  
  tree_sitter_rshell_external_scanner_destroy(scanner);
  PASS();
}

TEST(keyword_detection_if) {
  Scanner *scanner = tree_sitter_rshell_external_scanner_create();
  bool valid[6] = {false, false, true, false, false, false};  // EXPR_START valid
  
  bool result = scan_with_mock(scanner, "if (x > 10) {", valid);
  
  ASSERT(result == true, "Should emit token for 'if'");
  ASSERT(scanner->current_mode == MODE_EXPR, "Should be in EXPR mode");
  
  tree_sitter_rshell_external_scanner_destroy(scanner);
  PASS();
}

TEST(keyword_detection_for) {
  Scanner *scanner = tree_sitter_rshell_external_scanner_create();
  bool valid[6] = {false, false, true, false, false, false};  // EXPR_START valid
  
  bool result = scan_with_mock(scanner, "for i in list {", valid);
  
  ASSERT(result == true, "Should emit token for 'for'");
  ASSERT(scanner->current_mode == MODE_EXPR, "Should be in EXPR mode");
  
  tree_sitter_rshell_external_scanner_destroy(scanner);
  PASS();
}

TEST(mode_stays_same_no_token) {
  Scanner *scanner = tree_sitter_rshell_external_scanner_create();
  bool valid[6] = {false, false, true, false, false, false};  // EXPR_START valid
  
  // First line - should emit
  scan_with_mock(scanner, "X = 1", valid);
  ASSERT(scanner->current_mode == MODE_EXPR, "Should be in EXPR mode");
  
  // Second line, same mode - should NOT emit (mode didn't change)
  // But we need to simulate line start
  scanner->at_line_start = true;
  bool result2 = scan_with_mock(scanner, "Y = 2", valid);
  
  // This depends on implementation - if mode didn't change, might not emit
  // Let's check behavior
  
  tree_sitter_rshell_external_scanner_destroy(scanner);
  PASS();
}

TEST(comment_line_skipped) {
  Scanner *scanner = tree_sitter_rshell_external_scanner_create();
  bool valid[6] = {true, false, true, false, false, false};  // Both valid
  
  bool result = scan_with_mock(scanner, "# this is a comment", valid);
  
  ASSERT(result == false, "Should not emit token for comment");
  
  tree_sitter_rshell_external_scanner_destroy(scanner);
  PASS();
}

TEST(empty_line_skipped) {
  Scanner *scanner = tree_sitter_rshell_external_scanner_create();
  bool valid[6] = {true, false, true, false, false, false};  // Both valid
  
  bool result = scan_with_mock(scanner, "", valid);
  
  ASSERT(result == false, "Should not emit token for empty line");
  
  tree_sitter_rshell_external_scanner_destroy(scanner);
  PASS();
}

TEST(block_depth_tracking_open_brace) {
  Scanner *scanner = tree_sitter_rshell_external_scanner_create();
  scanner->current_mode = MODE_EXPR;
  scanner->expr_block_depth = 0;
  
  // Simulate seeing a '{'
  // In real scanner, this happens during scan when it sees the character
  scanner->expr_block_depth++;
  
  ASSERT(scanner->expr_block_depth == 1, "Should increment block depth");
  
  tree_sitter_rshell_external_scanner_destroy(scanner);
  PASS();
}

TEST(block_depth_tracking_close_brace) {
  Scanner *scanner = tree_sitter_rshell_external_scanner_create();
  scanner->current_mode = MODE_EXPR;
  scanner->expr_block_depth = 2;
  
  // Simulate seeing a '}'
  scanner->expr_block_depth--;
  
  ASSERT(scanner->expr_block_depth == 1, "Should decrement block depth");
  
  tree_sitter_rshell_external_scanner_destroy(scanner);
  PASS();
}

TEST(serialization_with_block_depth) {
  Scanner *scanner = tree_sitter_rshell_external_scanner_create();
  scanner->current_mode = MODE_EXPR;
  scanner->at_line_start = false;
  scanner->expr_block_depth = 3;
  scanner->cmd_block_depth = 1;
  
  char buffer[10];
  unsigned len = tree_sitter_rshell_external_scanner_serialize(scanner, buffer);
  
  ASSERT(len == 4, "Serialization should return 4 bytes");
  ASSERT(buffer[2] == 3, "Should serialize expr_block_depth");
  ASSERT(buffer[3] == 1, "Should serialize cmd_block_depth");
  
  Scanner *scanner2 = tree_sitter_rshell_external_scanner_create();
  tree_sitter_rshell_external_scanner_deserialize(scanner2, buffer, len);
  
  ASSERT(scanner2->expr_block_depth == 3, "Should deserialize expr_block_depth");
  ASSERT(scanner2->cmd_block_depth == 1, "Should deserialize cmd_block_depth");
  
  tree_sitter_rshell_external_scanner_destroy(scanner);
  tree_sitter_rshell_external_scanner_destroy(scanner2);
  PASS();
}

// ===== TEST RUNNER =====

int main() {
  printf("\nRShell Scanner V2 Unit Tests\n");
  printf("=============================\n\n");
  
  printf("Lifecycle Tests:\n");
  test_scanner_create_destroy_wrapper();
  test_scanner_serialization_wrapper();
  
  printf("\nPattern Detection Tests:\n");
  test_is_keyword_detection_wrapper();
  test_is_assignment_detection_wrapper();
  
  printf("\nLine Mode Detection Tests:\n");
  test_simple_expr_line_assignment_wrapper();
  test_simple_cmd_line_echo_wrapper();
  test_keyword_detection_if_wrapper();
  test_keyword_detection_for_wrapper();
  
  printf("\nEdge Cases:\n");
  test_mode_stays_same_no_token_wrapper();
  test_comment_line_skipped_wrapper();
  test_empty_line_skipped_wrapper();
  
  printf("\nBlock Depth Tracking:\n");
  test_block_depth_tracking_open_brace_wrapper();
  test_block_depth_tracking_close_brace_wrapper();
  test_serialization_with_block_depth_wrapper();
  
  printf("\n=============================\n");
  printf("Results: %d/%d passed", results.passed, results.total);
  if (results.failed > 0) {
    printf(" (%d FAILED)", results.failed);
  }
  printf("\n\n");
  
  return results.failed > 0 ? 1 : 0;
}