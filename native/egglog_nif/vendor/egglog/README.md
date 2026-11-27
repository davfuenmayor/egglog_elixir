# Local egglog library

The Rust library source comes from [egglog revision d89bc58](https://github.com/egraphs-good/egglog/tree/d89bc58adc9b9a87a8f571c5b9ad75d686d226e6).
The extraction command keeps each `ExtractedTerm` in `CommandOutput::ExtractVariants`.
This preserves the native cost, term ID and order already produced by the extractor.
The proof pipeline uses the same command and the display code prints the same terms.

This copy includes the library and its upstream MIT license. All library sources
except `src/lib.rs` match the pinned revision byte for byte. The other edits in
`src/lib.rs` remove CLI-only code. The sibling crates use the same Git revision.
The Hex package includes this crate, and its compile inputs are part of the native
source fingerprint used to validate release bundles.

When upstream exposes variant costs, switch Cargo back to the upstream Git
dependency, update the wrapper for the upstream result type, and remove this
directory and its packaging and fingerprint entries.
