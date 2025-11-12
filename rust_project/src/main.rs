use std::io::{self, Write};

fn main() {
    println!("Welcome to Rust Project!");
    println!("========================\n");

    // Basic calculator demo
    let a = 10;
    let b = 5;
    
    println!("Calculator Demo:");
    println!("{} + {} = {}", a, b, add(a, b));
    println!("{} - {} = {}", a, b, subtract(a, b));
    println!("{} * {} = {}", a, b, multiply(a, b));
    
    match divide(a, b) {
        Ok(result) => println!("{} / {} = {}", a, b, result),
        Err(e) => println!("Error: {}", e),
    }

    // String manipulation
    println!("\nString Demo:");
    let message = "Hello, Rust!";
    println!("Original: {}", message);
    println!("Uppercase: {}", message.to_uppercase());
    println!("Length: {}", message.len());

    // Vector operations
    println!("\nVector Demo:");
    let numbers = vec![1, 2, 3, 4, 5];
    println!("Numbers: {:?}", numbers);
    println!("Sum: {}", numbers.iter().sum::<i32>());
    println!("Max: {:?}", numbers.iter().max());

    // Interactive input
    println!("\nEnter your name:");
    print!("> ");
    io::stdout().flush().unwrap();
    
    let mut name = String::new();
    io::stdin()
        .read_line(&mut name)
        .expect("Failed to read line");
    
    println!("Hello, {}!", name.trim());
}

fn add(a: i32, b: i32) -> i32 {
    a + b
}

fn subtract(a: i32, b: i32) -> i32 {
    a - b
}

fn multiply(a: i32, b: i32) -> i32 {
    a * b
}

fn divide(a: i32, b: i32) -> Result<f64, String> {
    if b == 0 {
        Err("Cannot divide by zero".to_string())
    } else {
        Ok(a as f64 / b as f64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add() {
        assert_eq!(add(2, 3), 5);
        assert_eq!(add(-1, 1), 0);
    }

    #[test]
    fn test_subtract() {
        assert_eq!(subtract(5, 3), 2);
        assert_eq!(subtract(0, 5), -5);
    }

    #[test]
    fn test_multiply() {
        assert_eq!(multiply(4, 5), 20);
        assert_eq!(multiply(-2, 3), -6);
    }

    #[test]
    fn test_divide() {
        assert_eq!(divide(10, 2).unwrap(), 5.0);
        assert!(divide(5, 0).is_err());
    }
}
