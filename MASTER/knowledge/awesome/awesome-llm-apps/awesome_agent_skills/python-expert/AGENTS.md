#### ✅ Correct

The **Python‑Expert** agent is a specialised LLM‑driven assistant that excels at every aspect of Python development. It couples deep model knowledge with the Master toolbox to write, refactor, debug and optimise production‑ready Python code.

---

### Core Capabilities  

| Capability | Delivery |
|------------|----------|
| **Code Generation** | `WriteFile`, `StrReplace`, `AstEdit` emit PEP‑8‑compliant snippets, full modules or CLI scripts. |
| **Static Analysis** | Runs the `Lint` stage with a custom `PythonLinter` rule set (a `Master::Scan::Rule`) to surface style violations, unused imports and type‑hint gaps. |
| **Testing & Validation** | Generates `unittest`/`pytest` scaffolding, inserts assertions and executes the suite via the `Execute` stage, feeding results back to the `Council` for iterative improvement. |
| **Performance Optimisation** | Detects hot paths with the `Shell` tool (`cProfile`), suggests vectorised alternatives (NumPy, pandas) and applies `BatchReplace` for bulk refactors. |
| **Dependency Management** | Reads `requirements.txt` with `ReadFile`, proposes version upgrades and writes the updated file with `WriteFile`. |
| **Documentation** | Auto‑generates Google/NumPy‑style docstrings and README sections using `AskLlm` to summarise functionality. |
| **Debugging** | Parses tracebacks, pinpoints the failing line and applies an `AstEdit` patch to fix common errors such as off‑by‑one or wrong variable scope. |

---

### Toolchain Overview  

- **`AskLlm`** – Queries the DeepSeek model for conceptual explanations or design decisions.  
- **`ReadFile` / `WriteFile`** – Persistent I/O for source files and configuration.  
- **`AstEdit`** – Precise AST‑level transformations: rename, extract method, add type hints.  
- **`StrReplace`** – Fast string‑level refactors for import statements or magic numbers.  
- **`Shell`** – Executes linting (`flake8`), testing (`pytest`) and profiling (`cProfile`) in an isolated environment.  
- **`SearchFiles`** – Locates definitions, usages and TODO comments across the project tree.  

All tools are invoked through the **pipeline** stages (`Intake → Infer → Guard → Execute → Council → Lint → Memo → Render`). The **Result** monad (`Ok` / `Err`) guarantees deterministic error handling and makes the agent’s workflow observable via the **EventBus**.

---

### Typical Interaction Flow  

1. **User Prompt** – “Create a fast CSV parser that streams rows into a Pandas DataFrame.”  
2. **Intake** parses intent and selects the **Python‑Expert** persona from `Master::Council::Personas`.  
3. **Infer** picks the *code‑generation* mode (`Master::Reasoning::Modes`).  
4. **Guard** validates that no unsafe imports are requested (via `InjectionGuard`).  
5. **Execute** runs `WriteFile` to scaffold `csv_parser.py` and `StrReplace` to insert streaming logic.  
6. **Council** reviews the output, runs the `Lint` stage, and suggests missing type hints.  
7. **Lint** applies the suggestions, `Memo` caches the new file version, and `Render` returns the final diff to the user.  

---

### Best‑Practice Recommendations  

- **Always include type hints** – the agent auto‑adds them, but specifying expected signatures reduces ambiguity.  
- **Prefer functional decomposition** – `AstEdit` excels at extracting pure functions from monolithic blocks.  
- **Run `pytest --maxfail=1` early** – the `Execute` stage aborts on the first failing test, saving compute cycles.  
- **Leverage the `SemanticCache`** – repeated requests for the same utility (e.g., “read a JSON file”) are served from cache, accelerating response time.  

---

### Example Output (Diff)

```diff
--- a/csv_parser.py
+++ b/csv_parser.py
@@ -1,6 +1,9 @@
 import csv
+import pandas as pd
 from typing import Iterable, List
 
+def stream_csv(path: str, chunksize: int = 10_000) -> Iterable[pd.DataFrame]:
+    """Yield DataFrames chunk‑wise from a CSV file."""
+    for chunk in pd.read_csv(path, chunksize=chunksize):
+        yield chunk
-
-def parse_csv(path: str) -> List[dict]:
-    with open(path, newline='') as f:
-        reader = csv.DictReader(f)
-        return list(reader)
+def parse_csv(path: str) -> List[dict]:
+    """Legacy wrapper returning a list of rows for backward compatibility."""
+    return [row for df in stream_csv(path) for row in df.to_dict(orient='records')]
```

The diff adds **streaming**, **type hints**, and a **backward‑compatible wrapper**—the hallmarks of Python‑Expert output.

---

### Extending the Agent  

- **Add a new rule** under `lib/master/scan/rules/` (e.g., `PythonDocstringRule`) to enforce docstring style.  
- **Create a custom persona** in `lib/master/council/personas.rb` for “Data‑Science‑Guru” that tweaks `Reasoning::Modes` to favour vectorised NumPy solutions.  
- **Hook into `Master::Metrics`** to track average latency per Python generation request and set alerts via `Master::CircuitBreaker`.  

---

### Quick Reference Cheat‑Sheet  

| Command | Effect |
|---------|--------|
| `master run "write a Flask app with JWT auth"` | Generates a full Flask scaffold and adds `pyjwt` to `requirements.txt`. |
| `master run "refactor my loop to use list comprehension"` | Detects the loop and applies `StrReplace` to produce a one‑liner. |
| `master run "add type hints to my module"` | Scans the file, injects `: int`, `: str`, etc., and updates signatures. |
| `master run "benchmark this function"` | Executes `cProfile` via `Shell` and returns the top‑5 hot spots in a markdown table. |

---

*The Python‑Expert agent is a living, self‑optimising component of the Master framework. Follow the patterns above to harness its full power while keeping the system robust, observable and maintainable.*