# encoding: utf-8
# Dynamic schema manager for Weaviate

class SchemaManager
  def initialize(weaviate_client)
    @client = weaviate_client
  end

  def create_schema_for_profession(profession)
    schema = {
      "classes": [
        {
          "class": "#{profession}Data",
          "description": "Data related to the #{profession} profession",
          "properties": [
            {
              "name": "content",
              "dataType": ["text"],
              "indexInverted": true
            },
            {
              "name": "vector",
              "dataType": ["number"],
              "vectorIndexType": "hnsw",
              "vectorizer": "text2vec-transformers"
            }
          ]
        }
      ]
    }
    @client.schema.create(schema)
  end
end
