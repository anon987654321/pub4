## Placeholders

| Placeholder      | Purpose                                          | Recommended format                                              |
|------------------|--------------------------------------------------|-----------------------------------------------------------------|
| `{evaluation}`   | Concise summary of the current situation assessment. | Short sentence or bullet list (max 2 lines).                     |
| `{memory_content}`| Relevant facts retrieved from the agent’s memory. | Plain text; JSON fragment is acceptable when structured data is needed. |
| `{thought}`      | Chain‑of‑thought that justifies the chosen action. | Narrative sentence(s); keep the content on a single line inside the XML tag. |
| `{action_name}`  | Exact name of the tool, command, or function to invoke. | Identifier string that matches a registered tool (e.g., `SearchFiles`). |
| `{action_input}` | JSON‑serialised arguments required by the action. | Valid JSON object **without** surrounding quotes.                |

## Usage Guidelines

1. **Populate every placeholder** before sending the prompt to the LLM. Missing tags cause routing failures.  
2. **Maintain well‑formed XML**: avoid stray `<` or `>` characters inside values.  
3. **Validate JSON** in `<ActionInput>` with a quick parse to prevent runtime errors.  
4. **Do not modify `<Route>`** – it must remain `Action` so the system routes the response to the executor stage.  
5. **Escape special XML characters** (`&`, `<`, `>`) in text values using `&amp;`, `&lt;`, `&gt;`.  

## Example

```xml
<Prompt>
  <Evaluation>{evaluation}</Evaluation>
  <MemoryContent>{memory_content}</MemoryContent>
  <Thought>{thought}</Thought>
  <Route>Action</Route>
  <ActionName>{action_name}</ActionName>
  <ActionInput>{action_input}</ActionInput>
</Prompt>
```

*Replace the placeholders with concrete values that respect the formats above.*