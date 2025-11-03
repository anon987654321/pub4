/// A simple calculator library
pub mod calculator {
    /// Adds two numbers
    pub fn add(a: i32, b: i32) -> i32 {
        a + b
    }

    /// Subtracts b from a
    pub fn subtract(a: i32, b: i32) -> i32 {
        a - b
    }

    /// Multiplies two numbers
    pub fn multiply(a: i32, b: i32) -> i32 {
        a * b
    }

    /// Divides a by b, returns Result to handle division by zero
    pub fn divide(a: f64, b: f64) -> Result<f64, String> {
        if b == 0.0 {
            Err("Cannot divide by zero".to_string())
        } else {
            Ok(a / b)
        }
    }
}

/// String utilities
pub mod string_utils {
    /// Reverses a string
    pub fn reverse(s: &str) -> String {
        s.chars().rev().collect()
    }

    /// Checks if a string is a palindrome
    pub fn is_palindrome(s: &str) -> bool {
        let cleaned: String = s.chars()
            .filter(|c| c.is_alphanumeric())
            .flat_map(|c| c.to_lowercase())
            .collect();
        
        cleaned == reverse(&cleaned)
    }

    /// Counts words in a string
    pub fn word_count(s: &str) -> usize {
        s.split_whitespace().count()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculator_add() {
        assert_eq!(calculator::add(5, 3), 8);
    }

    #[test]
    fn test_calculator_divide() {
        assert_eq!(calculator::divide(10.0, 2.0).unwrap(), 5.0);
        assert!(calculator::divide(5.0, 0.0).is_err());
    }

    #[test]
    fn test_string_reverse() {
        assert_eq!(string_utils::reverse("hello"), "olleh");
    }

    #[test]
    fn test_palindrome() {
        assert!(string_utils::is_palindrome("racecar"));
        assert!(string_utils::is_palindrome("A man a plan a canal Panama"));
        assert!(!string_utils::is_palindrome("hello"));
    }

    #[test]
    fn test_word_count() {
        assert_eq!(string_utils::word_count("hello world"), 2);
        assert_eq!(string_utils::word_count("one"), 1);
    }
}
