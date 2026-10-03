# Legacy repository archaeology

Scope: `anon987654321/pub3`, `pub2`, and `pub`, plus the recovered `pub4` pre-collapse snapshot.

## pub4

- `main`: restored from the pre-collapse parent at `f131ff002293f93da47755e27e3a2b38b9828687`, retaining the two gate files from the collapse.
- `archaeology/pre-main-collapse-20261003`: exact pre-collapse snapshot.
- `fix/master-face-hands-free`: preserved older branch at `ba42c9560ea931932ee476083deb6ef81c47377f`.
- Collapse commit: `a98d45c8070ae2566fa51a34fdebffd3b196e0fb`. The tracked tree fell from roughly 5,477 entries to 6; `b4c510ef` restores the prior tree.

## pub3

- `main`: 513 tracked entries; one archive, `multimedia/dilla/tools/ffmpeg.zip` (22,560,768 bytes).
- `my-work`: 156 commits ahead / 189 behind `main`, tip `d1f2770fc43fd0e85e9d640d71e9b0748fd9712e`; 405 tracked entries and no archive paths, but a substantial historical media tree.
- `8fc6fc4463396a495b7c81e12c173dfbdf0185de`: added `sh/restore_backups.sh`.
- `87b55cceaf4d17faa515689ffee612dda4ff19a1`: merged the restore-content work.

## pub2

- `main`: 279 tracked entries; no `.tgz`, `.tar.gz`, or `.zip` paths.
- `818ea0d03770843a09e871c8a458f0cf5edc7985`: restored unique material from `__OLD_BACKUPS`, including AI3 framework/validation code, business plans, shared Rails utilities, and the J-Dilla carousel.
- `e53d3c144f8a2e3ed48cfb35acf0e2a3819e3abc`: later `master.json`/Rails restoration work.

## pub

- `main`: 157 archive paths, 122 unique archive blobs, totalling 311,059,494 bytes compressed.
- Duplicate archive paths share Git blob identities; extraction is therefore keyed by Git blob SHA.
- `21598560b57a78059df4dcd1751946914f91e179`: restored 2,878 lines of AI3 code from old-backup lineage.
- `a226fb3722242275bee11f6a0a2f8384f8d5e044`: restored the optimized `prompts.json` lineage.

## Archive inventory

| Repository | Path | Bytes | Git blob |
|---|---|---:|---|
| pub | `__OLD_BACKUPS/BRGEN_OLD.zip` | 34903820 | `4a68ac5d4313fe1de00067b665f13b29b31f5082` |
| pub | `__OLD_BACKUPS/__docs_20240804.tgz` | 5102262 | `e7aa575de0eb0f02634100965b597f10315ac312` |
| pub | `__OLD_BACKUPS/ai33/ai3_20250227.tgz` | 160817 | `ca3d8999fad493961e1f61ce3ba7997760877c90` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_correct_structure_ready.tgz` | 92910 | `2319b80d767db3e2a236ed0613ed25cc9edd3609` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_final_fleshed_out.tgz` | 94221 | `f3e9985020f2bdd7c923487355c52d4c5cd113d8` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_final_fully_inclusive.tgz` | 93681 | `51cc01376658eed3f7914f37cf2e14039e22db33` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_final_production_ready.tgz` | 92969 | `841de329f69a9b31658a54a21bf74f4727bd55ed` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_final_updated (1).tgz` | 94134 | `5417a52c95fd286b6cf095840be9644c315751ac` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_final_updated.tgz` | 91454 | `77711eb15b9c20bee13f58391dbac2e788da66ed` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_fleshed_out_full (1).tgz` | 94275 | `fde302cba5cb556c32013c5e233f53371adb068a` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_fleshed_out_full.tgz` | 94275 | `fde302cba5cb556c32013c5e233f53371adb068a` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_full_improved_ready.tgz` | 92361 | `abb542aa5a23c2e374141cf9be82e7897d84e9ba` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_fully_complete_and_embellished.tgz` | 93612 | `f1d04b47f418b3cade79bff0ef7a3a0d96e5eac0` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_fully_embellished_ready.tgz` | 92746 | `41764ae5e4a09d6b027c0802243b6c6d293b30f5` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_fully_fleshed_and_final.tgz` | 93426 | `4dbc68434f9ecabfaa29dffc6f916da45c59dbc3` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_fully_fleshed_out_ready.tgz` | 93298 | `3e69f582548474ea0d160459b3c0d58d292da778` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_production_ready.tgz` | 92079 | `79f44f566ddfcda7a6a365135758997385cc9041` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20240930_viz_production_ready.tgz` | 90474 | `688ee07e0a7ad81c8b01d0f5da1213a70b492c90` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20241002_further_refined.tgz` | 3135374 | `fdd34d8990e58f47aa26457cd501dcdcb89bc0e4` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20241002_updated.tgz` | 3135348 | `4305248f5af9ae05bdc4d6baf36c2a067912ab00` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_20241019.tgz` | 7356559 | `13d2d9ad894209c88fd3749b1fc9815eddda6e02` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_CONSOLIDATED_FINAL.tgz` | 7347782 | `3e095273f6236adef5102d9aa71d00be032799ce` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_FINAL_COMPLETE.tgz` | 14671137 | `282deb3a58c24e699a039148f0fb3e0768df8af9` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_FINAL_COMPLETE_V2.tgz` | 1657 | `d09e61012b88686d9c31e74de5ba958f5147a984` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_FINAL_CORRECTED_V2.tgz` | 7348467 | `cb9061d8c59f112d681a9925c9f66ed2e1d5b28d` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_FINAL_REFINED.tgz` | 7346254 | `b54045896394fb0da126c7224c801f3e86a6ac0c` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_FINAL_WITH_ASSISTANTS.tgz` | 7346262 | `865e082d31d2ffd6e5993a3981e0ff2c40848d83` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_FINAL_WITH_UPDATED_README.tgz` | 7346266 | `c21a371ee219ff036985af64e5a0ce39e253cc26` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_FINAL_v2.tgz` | 7347499 | `5623485d88d793a74d45a28649929e03b51b7a9b` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_Improved_FINAL.tgz` | 7345975 | `f7261ce3a0687836c401f8054b3aa2411d968f0a` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_LANGCHAIN_INTEGRATED.tgz` | 7346261 | `08193d44933d443e29ac28cf732145d024e10149` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_LIB_UPDATED_FINAL.tgz` | 7346258 | `eaf252f14d30fba8ac49edf98347e1aa1464bcdd` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_NEW.tgz` | 7348357 | `e6143a0f544e87b24d20b002aa5f89d403f3c56e` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_PERSONAL_ASSISTANT_UPDATED.tgz` | 7346267 | `20eb0b4752e7dad74b199646040292796d360453` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_PRODUCTION_READY_V1.tgz` | 7348468 | `38ba5e729222046f7188072c154a0b24830992a5` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_RESTORED_FINAL.tgz` | 7346255 | `f28ca32b56059d230bc1c80e8d8c3f35ab215088` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_assistants_progress.tgz` | 533 | `798c8fbbe8db25a34744ae0b9aa3e55618385506` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_cli_files.tgz` | 2186 | `61522e9c34a9ae29f3b24f17415c9fdc4e0214a0` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_cli_project_complete.tgz` | 1721 | `b229c775c453f45220e063ca9f113f76af57ea87` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_cli_project_latest.tgz` | 1652 | `652fcce5cb3b43e32744586090d642cff4463bb4` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_cli_project_with_structure.tgz` | 2301 | `332aad157ed060b87f0b691ccaa6a24853f0dd8d` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_code_v1.tgz` | 3044 | `2dbe0d90b176988585af3a76976539f93ef90a5b` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_consolidated_code_cleaned.tgz` | 168655 | `28b6a2976aa58f5c4f9e1de56ba503e3524499e2` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_consolidated_code_cleaned_v2.tgz` | 168532 | `f5f197a61d309feda17605d96241b2dff6fc711b` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_consolidated_code_merged.tgz` | 192729 | `5b0e789de486fcb6f672fd3197469c90dac90a38` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_consolidated_code_v2.tgz` | 194831 | `e80e0f12004e0b81698c3f70a92d488a26836e95` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_corrected_full_project_with_lib.tgz` | 4365 | `541376ba7568d73ea0b1f7303d2e896e93ba0ffa` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_files.tgz` | 1463 | `235b5f8872acac3403eb325f8db69835e2f1f493` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_files_corrected.tgz` | 2201 | `8839da3aaa66838e1e6b2f5242bc285311a2eefe` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_complete_project_files.tgz` | 2141 | `ca35cef075df876d588b2c05a8f9aea10192600b` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_consolidated.tgz` | 971 | `00c260f2e6bd03275378acdd3f3ad29cff35d848` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_consolidated_project_files.tgz` | 2797 | `8d872f86c0f6ed50e90103da51eeb963f3d3b9b8` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_corrected_project_files.tgz` | 2477 | `1f7bb2aa0890554bedbafc5ad136862855a20b16` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_deployment.tgz` | 143566 | `a8c775e95900674952e77dcd9618dc58592628a2` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_fleshed_package.tgz` | 4660 | `34745868cf05dfbb964c9733f0500da19d669d09` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_fully_traced.tgz` | 2532 | `23d33913630df0a931462bf62560b163438d045b` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_fully_updated.tgz` | 2528 | `933540eb5a5d19609ca1a06281617d609529aeac` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_latest_corrected_project_files.tgz` | 4692 | `3ac01705ec0b566c5a20a8660971873a9da64c3f` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_no_lib_assistants_deployment.tgz` | 96949 | `829f25d0e8285ae1378582532aacbfc166ce5ec9` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_output.tgz` | 1464 | `61f178d75b25edf9fbe4d4c27530d3dcd3f1d9db` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_update_no_git_deployment.tgz` | 20410 | `aa276949c919d3aaadb57ad8a734227198abf1d2` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_updated.tgz` | 175881 | `8d5d06cd501b4eddb9e7c40f99232589fed84525` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_final_verified_deployment.tgz` | 144233 | `62fb23346c823843b5b92485fa0c429d0096b7ce` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_full_project.tgz` | 43083 | `7c497d1d3703d884b48c05c76b7d71fd67fdb450` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_fully_consolidated_deployment.tgz` | 143609 | `d6ba4119c64a234007c7d67c3a4433aaa5d1aa99` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_fully_fleshed_out.tgz` | 176671 | `c3bb111008ac4e815815ac78aaa232848dcca29c` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_improvements.tgz` | 3148196 | `6193690cd22e4fc1a6aa63ed4e30913eea96a945` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_langchainrb_integration.tgz` | 3151238 | `a2dfb4bf6e82ec3b227d907be22e2d68a6cea7d1` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_modified_files.tgz` | 3323856 | `d18cfa1cf1a33f209d697ff60bc410359aaafbb0` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_refined_final_deployment.tgz` | 144189 | `7e688aa231e0983dc40343619f92b8e0ff93faa1` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_refined_final_no_lib_assistants_deployment (1).tgz` | 96918 | `bf5206120d03a35eb19be48b0bac463c2e8f0ccf` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_refined_final_no_lib_assistants_deployment.tgz` | 96918 | `bf5206120d03a35eb19be48b0bac463c2e8f0ccf` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_refined_final_with_consistent_assistants.tgz` | 100486 | `ef3c47f545b3e42e8932c4571e8993b3139ab10c` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_refined_no_git_20241010.tgz` | 7306667 | `21cd37cf60134486c74d3abca8318196838ad96f` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_refined_with_reintroduced_assistants_deployment.tgz` | 100328 | `fd6d60b7f6fa1343bdba60f70fd3bf1846e11319` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_refined_with_shared_assistants.tgz` | 105732 | `dab6c5baa6f9f52c02ea742ad7beac1700794717` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_updated_improvements.tgz` | 94887 | `237477e0e082408f057af113c3461573c1110631` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_with_agents_and_prompts (1).tgz` | 3151818 | `53668b72e656221a7a594c659cc3d692f4a4620a` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/__backups/ai3_with_agents_and_prompts.tgz` | 3151818 | `53668b72e656221a7a594c659cc3d692f4a4620a` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/assistants/OUTPUT_assistants_2024-11-18.md_20241119.tgz` | 16615 | `89cda30d1e485f8eac1392397c5d1f3eb5865168` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/assistants/ai3_assistants_progress.tgz` | 533 | `798c8fbbe8db25a34744ae0b9aa3e55618385506` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/assistants/ai3_final_no_lib_assistants_deployment.tgz` | 96949 | `829f25d0e8285ae1378582532aacbfc166ce5ec9` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/assistants/ai3_final_package_with_expanded_assistants.tgz` | 4492 | `3a9be525285abfed81e2da8762facb7e2923c05c` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/assistants/ai3_final_package_with_restored_assistants.tgz` | 4107 | `c952f41d9d2c446d5c978e7ee6bf4f92355592dc` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/assistants/ai3_refined_final_no_lib_assistants_deployment (1).tgz` | 96918 | `bf5206120d03a35eb19be48b0bac463c2e8f0ccf` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/assistants/ai3_refined_final_no_lib_assistants_deployment.tgz` | 96918 | `bf5206120d03a35eb19be48b0bac463c2e8f0ccf` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/assistants/ai3_refined_final_with_consistent_assistants.tgz` | 100486 | `ef3c47f545b3e42e8932c4571e8993b3139ab10c` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/assistants/ai3_refined_with_reintroduced_assistants_deployment.tgz` | 100328 | `fd6d60b7f6fa1343bdba60f70fd3bf1846e11319` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/assistants/ai3_refined_with_shared_assistants.tgz` | 105732 | `dab6c5baa6f9f52c02ea742ad7beac1700794717` |
| pub | `__OLD_BACKUPS/ai33/ai3_old/assistants/assistants.zip` | 8196 | `497e9711e791e64d7ea749e8e0a1dceee2010b0f` |
| pub | `__OLD_BACKUPS/ai33/consolidated_ai3_refactored.tgz` | 1396 | `4051367666a56c8d3b61b093ceded2727cccaeba` |
| pub | `__OLD_BACKUPS/ai33/consolidated_final_ai3.tgz` | 132020 | `cce4ee7b9cbd6147f107b2bff143ce7de7479329` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240601.tgz` | 145833 | `bbcaf82669b5d6c0d52ee8ac19227efa3189036f` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240603.tgz` | 214416 | `d6ddc48cf0ff7fe234999703d82619a40ce07079` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240604.tgz` | 214634 | `8381f857149d3d348c593d1811ddde45e6eb46f3` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240607.tgz` | 239128 | `69e2be34ee6fa882d336dbea4046fed751d53920` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240609.tgz` | 270478 | `6414bc53a279dd97d32a0f3d13fbcb9fe65cb6e4` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240610.tgz` | 269637 | `8ab9d77accce9da18cc061c07cd5a2ca6eaccd58` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240612.tgz` | 1080564 | `adbc5523c8bd241e576c6799f482cb6315d491e5` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240613.tgz` | 1080564 | `adbc5523c8bd241e576c6799f482cb6315d491e5` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240615.tgz` | 1080610 | `3e4e5562fd45670832e614e560f18a145e699b10` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240617.tgz` | 2167962 | `ecc294d98348b5fa96d75500de177d32e9d29583` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240618.tgz` | 2167893 | `7b54509543738d2fbdb40e55170e078fec04cc9b` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240621.tgz` | 2148900 | `2e5f7014fdd70f1952605f197ca51fcef7ab8fb1` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240622.tgz` | 2148901 | `944cde7ecc3b977723368d7874f171d2fd56afd5` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240804.tgz` | 2183873 | `7fa5b80aba256810064bd387fcd56dae1126d02b` |
| pub | `__OLD_BACKUPS/ai33/egpt_20240806.tgz` | 2183873 | `7fa5b80aba256810064bd387fcd56dae1126d02b` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240601.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240603.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240604.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240607.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240609.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240610.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240612.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240613.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240615.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240617.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240618.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240621.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/egpt_OLD_20240622.tgz` | 16560 | `a74c46d0b5ecc3f5ee21487ad2a250730518d1f1` |
| pub | `__OLD_BACKUPS/ai33/ex1.zip` | 18664 | `eebefe5ba2b9a76ee775e2db92e0601c0ae12b34` |
| pub | `__OLD_BACKUPS/ai33/final_refined_ai3_package.tgz` | 36156 | `7fdab505e3606c407ba1c4dc904cc88a22b5bc97` |
| pub | `__OLD_BACKUPS/ai33/final_streamlined_ai3_production_ready.tgz` | 33341 | `9dbff154d7380a16e5ea83d54a3162e67b32ebfe` |
| pub | `__OLD_BACKUPS/arch_20240622.tgz` | 39948703 | `fbd6846ad7e03276c5be7a775ef3819a7a6bd2f6` |
| pub | `__OLD_BACKUPS/brgen_ANCIENT_20240622.tgz` | 34453827 | `a5528c58d7a0248d54f5fcdf056a5c8dcbbaa7fb` |
| pub | `__OLD_BACKUPS/dev_20240804.tgz` | 123 | `ae356fcdc734451bd2c08067a4334977689c925a` |
| pub | `__OLD_BACKUPS/egpt_20240804.tgz` | 2183873 | `7fa5b80aba256810064bd387fcd56dae1126d02b` |
| pub | `__OLD_BACKUPS/egpt_20240806.tgz` | 2183873 | `7fa5b80aba256810064bd387fcd56dae1126d02b` |
| pub | `__OLD_BACKUPS/loose_files_20240804.tgz` | 4193 | `a66390b56d0253eb0c50021334b1cb74de7ea0d5` |
| pub | `__OLD_BACKUPS/loose_files_20240806.tgz` | 4027 | `38ac7ffc028eba6cf8fd8b183b520f2136c44834` |
| pub | `__OLD_BACKUPS/openbsd_20240726.tgz` | 90548 | `baeaeabc39001534fd1623f00741b64b4232e762` |
| pub | `__OLD_BACKUPS/openbsd_20240804.tgz` | 90859 | `78929a86f01500338aa7cd0a06e6008b466d47cd` |
| pub | `__OLD_BACKUPS/openbsd_20240806.tgz` | 96600 | `2edeb82f1fcd60833ea1476b49ce135877573e87` |
| pub | `__OLD_BACKUPS/rails___shared_20240804.tgz` | 6452 | `01cd239f7e0a4dc336351ee46335e431100c0b14` |
| pub | `__OLD_BACKUPS/rails___shared_20240806.tgz` | 6167 | `7d9d45bcc5a944ead466cd211bc5c351270f3db7` |
| pub | `__OLD_BACKUPS/rails_amber_20240803.tgz` | 156283 | `cb0c17997362ce120a62884f6c253930840b8763` |
| pub | `__OLD_BACKUPS/rails_amber_20240804.tgz` | 156216 | `2aa00c7f81c70fb3d2318117972585d8b4f31209` |
| pub | `__OLD_BACKUPS/rails_amber_20240806.tgz` | 165353 | `cc9dab524f31099221b192802a829acd519c6975` |
| pub | `__OLD_BACKUPS/rails_blognet_20240804.tgz` | 925 | `00f67dad310ec67a95cfb2a1d49331fbc3d084fd` |
| pub | `__OLD_BACKUPS/rails_blognet_20240806.tgz` | 925 | `00f67dad310ec67a95cfb2a1d49331fbc3d084fd` |
| pub | `__OLD_BACKUPS/rails_brgen_20240804.tgz` | 73567 | `0c5ffd3be31d58281eff0d3ef31c1469a3cb73bc` |
| pub | `__OLD_BACKUPS/rails_brgen_20240806.tgz` | 73567 | `0c5ffd3be31d58281eff0d3ef31c1469a3cb73bc` |
| pub | `__OLD_BACKUPS/rails_brgen_dating_20240804.tgz` | 1563 | `37184f06b63caf30373eeac8f26214fcf15eee94` |
| pub | `__OLD_BACKUPS/rails_brgen_dating_20240806.tgz` | 1563 | `37184f06b63caf30373eeac8f26214fcf15eee94` |
| pub | `__OLD_BACKUPS/rails_brgen_marketplace_20240804.tgz` | 1181 | `203979185ab17e9d061c7707a325cb32f61decff` |
| pub | `__OLD_BACKUPS/rails_brgen_marketplace_20240806.tgz` | 1181 | `203979185ab17e9d061c7707a325cb32f61decff` |
| pub | `__OLD_BACKUPS/rails_brgen_playlist_20240804.tgz` | 5559 | `a2e328f0f81fbfae7ba9b487551a6f618b9b825d` |
| pub | `__OLD_BACKUPS/rails_brgen_playlist_20240806.tgz` | 5559 | `a2e328f0f81fbfae7ba9b487551a6f618b9b825d` |
| pub | `__OLD_BACKUPS/rails_brgen_takeaway_20240804.tgz` | 739 | `0a44ad158d7ab8f102bca8a40bc9b4cb597f13e0` |
| pub | `__OLD_BACKUPS/rails_brgen_takeaway_20240806.tgz` | 739 | `0a44ad158d7ab8f102bca8a40bc9b4cb597f13e0` |
| pub | `__OLD_BACKUPS/rails_brgen_tv_20240804.tgz` | 158 | `98ffb2a7265fd8d0b0ac05b56c68976823821e0e` |
| pub | `__OLD_BACKUPS/rails_brgen_tv_20240806.tgz` | 158 | `98ffb2a7265fd8d0b0ac05b56c68976823821e0e` |
| pub | `__OLD_BACKUPS/rails_bsdports_20240804.tgz` | 4917 | `d1e09e19a156c595139f9bb3d3207df12c245138` |
| pub | `__OLD_BACKUPS/rails_bsdports_20240806.tgz` | 4917 | `d1e09e19a156c595139f9bb3d3207df12c245138` |
| pub | `__OLD_BACKUPS/sh_20240804.tgz` | 29387 | `2e938b842231d01e69d1a60f2c959e6d7a9353af` |
| pub | `__OLD_BACKUPS/sh_20240806.tgz` | 29387 | `2e938b842231d01e69d1a60f2c959e6d7a9353af` |
| pub | `postpro/cameras_lightroom_vsco.tgz` | 21551820 | `947ccb3afc09b8bc46a179eb0ed9f611f37e651e` |
| pub3 | `multimedia/dilla/tools/ffmpeg.zip` | 22560768 | `3b5c878fe2b957ccf4a84b9c291da6ce68c89b1c` |

## Disposition

Do not bulk-copy these archives into `pub4`. Extract them into a separate working area, compare against current and historical trees, and promote only material with evidence of unique value.

Binary extraction is delegated to `MASTER/tools/archaeology/extract_legacy_archives.zsh` so the old repositories can be processed without turning `pub4` into another backup dump.