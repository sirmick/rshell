use rustler::{Atom, Env, Error, NifResult, ResourceArc, Term};
use std::collections::HashMap;
use std::sync::Mutex;
use tree_sitter::{InputEdit, Parser, Point, Range, Tree};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        buffer_overflow,
        parse_error,
        no_tree,
    }
}

/// ParserResource holds the parser state for incremental parsing
/// Uses Mutex for thread-safe access from NIF calls
pub struct ParserResource {
    parser: Mutex<Parser>,
    old_tree: Mutex<Option<Tree>>,
    accumulated_input: Mutex<String>,
    max_buffer_size: usize,
}

impl ParserResource {
    fn new(max_buffer_size: usize) -> Result<Self, String> {
        let mut parser = Parser::new();
        let bash_language = tree_sitter_bash::LANGUAGE.into();
        
        parser.set_language(&bash_language)
            .map_err(|_| "Failed to set Bash language")?;
        
        Ok(ParserResource {
            parser: Mutex::new(parser),
            old_tree: Mutex::new(None),
            accumulated_input: Mutex::new(String::new()),
            max_buffer_size,
        })
    }
}

/// Create a new parser resource with default buffer size (10MB)
#[rustler::nif]
fn new_parser() -> NifResult<(Atom, ResourceArc<ParserResource>)> {
    match ParserResource::new(10 * 1024 * 1024) {
        Ok(resource) => Ok((atoms::ok(), ResourceArc::new(resource))),
        Err(msg) => Err(Error::Term(Box::new(msg))),
    }
}

/// Create a new parser resource with custom buffer size
#[rustler::nif]
fn new_parser_with_size(
    max_buffer_size: usize
) -> NifResult<(Atom, ResourceArc<ParserResource>)> {
    match ParserResource::new(max_buffer_size) {
        Ok(resource) => Ok((atoms::ok(), ResourceArc::new(resource))),
        Err(msg) => Err(Error::Term(Box::new(msg))),
    }
}

/// Parse incrementally by appending a fragment to accumulated input
/// Uses tree-sitter's incremental parsing with InputEdit tracking
#[rustler::nif]
fn parse_incremental<'env>(
    env: Env<'env>,
    resource: ResourceArc<ParserResource>,
    fragment: String,
) -> NifResult<(Atom, HashMap<String, Term<'env>>)> {
    use rustler::Encoder;
    
    // Get old input length and calculate row count for InputEdit
    let (old_len, old_row_count) = {
        let input = resource.accumulated_input.lock().unwrap();
        let row_count = input.matches('\n').count();
        (input.len(), row_count)
    };
    
    // Check buffer size before appending
    {
        let input = resource.accumulated_input.lock().unwrap();
        if input.len() + fragment.len() > resource.max_buffer_size {
            return Ok((atoms::error(), {
                let mut map = HashMap::new();
                map.insert("reason".to_string(), "buffer_overflow".encode(env));
                map.insert("current_size".to_string(), input.len().encode(env));
                map.insert("fragment_size".to_string(), fragment.len().encode(env));
                map.insert("max_size".to_string(), resource.max_buffer_size.encode(env));
                map
            }));
        }
    }
    
    // Append fragment to accumulated input
    let new_len = {
        let mut input = resource.accumulated_input.lock().unwrap();
        input.push_str(&fragment);
        input.len()
    };
    
    // Calculate new row count after append
    let new_row_count = {
        let input = resource.accumulated_input.lock().unwrap();
        input.matches('\n').count()
    };
    
    // Create InputEdit for tree-sitter's incremental parsing
    let input_edit = InputEdit {
        start_byte: old_len,
        old_end_byte: old_len,
        new_end_byte: new_len,
        start_position: Point {
            row: old_row_count,
            column: 0,
        },
        old_end_position: Point {
            row: old_row_count,
            column: 0,
        },
        new_end_position: Point {
            row: new_row_count,
            column: 0,
        },
    };
    
    // Get old tree and apply edit (updates tree metadata for incremental parsing)
    let old_tree_option = {
        let mut tree_lock = resource.old_tree.lock().unwrap();
        if let Some(ref mut old_tree) = *tree_lock {
            // Apply edit to old tree's metadata - required for incremental parsing
            old_tree.edit(&input_edit);
        }
        tree_lock.clone()
    };
    
    // Parse with old_tree as reference (tree-sitter reuses unchanged subtrees internally)
    let input = resource.accumulated_input.lock().unwrap().clone();
    let mut parser = resource.parser.lock().unwrap();
    
    match parser.parse(&input, old_tree_option.as_ref()) {
        Some(new_tree) => {
            let has_error = new_tree.root_node().has_error();
            let ast = convert_node_to_map(&new_tree.root_node(), &input, env);
            
            // Extract changed ranges if we have an old tree
            let changed_ranges = if let Some(ref old_tree) = old_tree_option {
                extract_changed_ranges(&new_tree, old_tree, env)
            } else {
                // First parse - everything is new
                vec![]
            };
            
            // Store the new tree
            {
                let mut tree_lock = resource.old_tree.lock().unwrap();
                *tree_lock = Some(new_tree);
            }
            
            // Build result with AST and change metadata
            let mut result = ast.clone();
            if has_error {
                result.insert("has_errors".to_string(), true.encode(env));
            }
            result.insert("changed_ranges".to_string(), changed_ranges.encode(env));
            
            Ok((atoms::ok(), result))
        }
        None => {
            Ok((atoms::error(), {
                let mut map = HashMap::new();
                map.insert("reason".to_string(), "parse_error".encode(env));
                map
            }))
        }
    }
}

/// Reset the parser state (clear accumulated input and old tree)
#[rustler::nif]
fn reset_parser(resource: ResourceArc<ParserResource>) -> Atom {
    {
        let mut input = resource.accumulated_input.lock().unwrap();
        input.clear();
    }
    
    {
        let mut tree_lock = resource.old_tree.lock().unwrap();
        *tree_lock = None;
    }
    
    atoms::ok()
}

/// Get the current AST without parsing (from last parse result)
#[rustler::nif]
fn get_current_ast<'env>(
    env: Env<'env>,
    resource: ResourceArc<ParserResource>,
) -> NifResult<(Atom, HashMap<String, Term<'env>>)> {
    let tree_lock = resource.old_tree.lock().unwrap();
    
    match tree_lock.as_ref() {
        Some(tree) => {
            let input = resource.accumulated_input.lock().unwrap();
            let ast = convert_node_to_map(&tree.root_node(), &input, env);
            Ok((atoms::ok(), ast))
        }
        None => {
            use rustler::Encoder;
            Ok((atoms::error(), {
                let mut map = HashMap::new();
                map.insert("reason".to_string(), "no_tree".encode(env));
                map
            }))
        }
    }
}

/// Check if current tree has errors
#[rustler::nif]
fn has_errors(resource: ResourceArc<ParserResource>) -> bool {
    let tree_lock = resource.old_tree.lock().unwrap();
    match tree_lock.as_ref() {
        Some(tree) => tree.root_node().has_error(),
        None => false,
    }
}

/// Get accumulated input size
#[rustler::nif]
fn get_buffer_size(resource: ResourceArc<ParserResource>) -> usize {
    let input = resource.accumulated_input.lock().unwrap();
    input.len()
}

/// Get accumulated input content
#[rustler::nif]
fn get_accumulated_input(resource: ResourceArc<ParserResource>) -> String {
    let input = resource.accumulated_input.lock().unwrap();
    input.clone()
}

/// Original synchronous parse function (kept for backward compatibility)
#[rustler::nif]
fn parse_bash<'env>(env: Env<'env>, content: String) -> NifResult<(Atom, HashMap<String, Term<'env>>)> {
    let mut parser = Parser::new();
    let bash_language = tree_sitter_bash::LANGUAGE.into();
    
    if parser.set_language(&bash_language).is_err() {
        return Err(Error::Atom("failed_to_set_language"));
    }

    match parser.parse(&content, None) {
        Some(tree) => {
            if tree.root_node().has_error() {
                Ok((atoms::error(), HashMap::new()))
            } else {
                let ast = convert_node_to_map(&tree.root_node(), &content, env);
                Ok((atoms::ok(), ast))
            }
        }
        None => {
            Err(Error::Atom("failed_to_parse"))
        }
    }
}

// Helper function to convert tree-sitter node to Elixir map
fn convert_node_to_map<'env>(
    node: &tree_sitter::Node,
    source: &str,
    env: Env<'env>
) -> HashMap<String, Term<'env>> {
    use rustler::Encoder;
    
    let mut result = HashMap::new();
    
    let start = node.start_position();
    let end = node.end_position();
    let text = node.utf8_text(source.as_bytes()).unwrap_or("");
    
    // Use "type" to match Elixir typed struct expectations
    result.insert("type".to_string(), node.kind().encode(env));
    result.insert("start_row".to_string(), start.row.encode(env));
    result.insert("start_col".to_string(), start.column.encode(env));
    result.insert("end_row".to_string(), end.row.encode(env));
    result.insert("end_col".to_string(), end.column.encode(env));
    result.insert("text".to_string(), text.encode(env));
    
    // Extract ALL named fields automatically using tree-sitter's field metadata
    extract_all_node_fields(node, source, &mut result, env);
    
    result
}

fn extract_all_node_fields<'env>(
    node: &tree_sitter::Node,
    source: &str,
    result: &mut HashMap<String, Term<'env>>,
    env: Env<'env>
) {
    use rustler::Encoder;
    use std::collections::HashMap as StdHashMap;
    
    let mut field_map: StdHashMap<String, Vec<HashMap<String, Term<'env>>>> = StdHashMap::new();
    let mut unnamed_children: Vec<HashMap<String, Term<'env>>> = Vec::new();
    
    // Use cursor to iterate with field names
    let mut cursor = node.walk();
    let has_children = cursor.goto_first_child();
    
    if has_children {
        loop {
            let child = cursor.node();
            
            // Skip unnamed nodes (like punctuation)
            if child.is_named() {
                // Get field name for this child from cursor
                if let Some(field_name) = cursor.field_name() {
                    // Named field
                    let child_map = convert_node_to_map(&child, source, env);
                    field_map
                        .entry(field_name.to_string())
                        .or_insert_with(Vec::new)
                        .push(child_map);
                } else {
                    // Unnamed child (e.g., children of program node)
                    let child_map = convert_node_to_map(&child, source, env);
                    unnamed_children.push(child_map);
                }
            }
            
            if !cursor.goto_next_sibling() {
                break;
            }
        }
    }
    
    // Add named fields to result - single value or list
    for (field_name, values) in field_map {
        if values.len() == 1 {
            result.insert(field_name, values[0].clone().encode(env));
        } else {
            result.insert(field_name, values.encode(env));
        }
    }
    
    // Add unnamed children as "children" field if any exist
    if !unnamed_children.is_empty() {
        result.insert("children".to_string(), unnamed_children.encode(env));
    }
}

/// Extract changed ranges from tree-sitter's incremental parsing
/// Returns byte offsets and positions of modified AST subtrees
fn extract_changed_ranges<'env>(
    new_tree: &Tree,
    old_tree: &Tree,
    env: Env<'env>,
) -> Vec<HashMap<String, Term<'env>>> {
    use rustler::Encoder;
    
    let ranges: Vec<Range> = new_tree.changed_ranges(old_tree).collect();
    
    ranges
        .iter()
        .map(|range| {
            let mut map = HashMap::new();
            map.insert("start_byte".to_string(), range.start_byte.encode(env));
            map.insert("end_byte".to_string(), range.end_byte.encode(env));
            map.insert("start_row".to_string(), range.start_point.row.encode(env));
            map.insert("start_col".to_string(), range.start_point.column.encode(env));
            map.insert("end_row".to_string(), range.end_point.row.encode(env));
            map.insert("end_col".to_string(), range.end_point.column.encode(env));
            map
        })
        .collect()
}

rustler::init!(
    "Elixir.BashParser",
    [
        parse_bash,
        new_parser,
        new_parser_with_size,
        parse_incremental,
        reset_parser,
        get_current_ast,
        has_errors,
        get_buffer_size,
        get_accumulated_input,
    ],
    load = load_resources
);

fn load_resources(env: Env, _: Term) -> bool {
    rustler::resource!(ParserResource, env);
    true
}
