# frozen_string_literal: true

# Weaviate Wrapper - Compatibility wrapper for existing assistants
# This provides backward compatibility for assistants expecting weaviate_wrapper

require_relative 'weaviate_integration'

# Backward compatibility alias
WeaviateWrapper = WeaviateIntegration
