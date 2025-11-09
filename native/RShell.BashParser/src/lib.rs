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
    
    result.insert("kind".to_string(), node.kind().encode(env));
    result.insert("text".to_string(), node.utf8_text(source.as_bytes()).unwrap_or("").encode(env));
    result.insert("start_row".to_string(), start.row.encode(env));
    result.insert("start_col".to_string(), start.column.encode(env));
    result.insert("end_row".to_string(), end.row.encode(env));
    result.insert("end_col".to_string(), end.column.encode(env));
    
    let mut children = Vec::new();
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        children.push(convert_node_to_map(&child, source, env));
    }
    result.insert("children".to_string(), children.encode(env));
    
    result
}

rustler::init!("Elixir.BashParser", [parse_bash]);
