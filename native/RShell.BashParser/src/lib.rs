use rustler::{Atom, Env, NifResult, Term};
use std::collections::HashMap;

mod atoms {
    rustler::atoms! {
        ok,
        error,
    }
}

#[rustler::nif]
fn parse_bash<'env>(env: Env<'env>, content: String) -> NifResult<(Atom, HashMap<String, Term<'env>>)> {
    let mut parser = tree_sitter::Parser::new();

    let bash_language = tree_sitter_bash::LANGUAGE.into();
    
    if let Err(_) = parser.set_language(&bash_language) {
        return Err(rustler::Error::Atom("failed_to_set_language"));
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
            Err(rustler::Error::Atom("failed_to_parse"))
        }
    }
}

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

// Old field extraction functions removed - now using extract_all_node_fields

rustler::init!("Elixir.BashParser", [parse_bash]);
