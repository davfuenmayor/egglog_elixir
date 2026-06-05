use std::collections::BTreeMap;

use egglog::CommandOutput;

pub fn output_kind(output: &CommandOutput) -> &'static str {
    match output {
        CommandOutput::PrintFunctionSize(_) => "print_size",
        CommandOutput::PrintAllFunctionsSize(_) => "print_all_sizes",
        CommandOutput::ExtractBest(_, _, _) => "extract",
        CommandOutput::ExtractVariants(_, _) => "extract_variants",
        CommandOutput::ProveExists { .. } => "proof",
        CommandOutput::OverallStatistics(_) => "overall_statistics",
        CommandOutput::PrintFunction(_, _, _, _) => "print_function",
        CommandOutput::RunSchedule(_) => "run_schedule",
        CommandOutput::UserDefined(_) => "user_defined",
    }
}

pub fn add_output_report_stats(outputs: &[CommandOutput], numeric_stats: &mut Vec<(String, i64)>) {
    let mut iterations = 0_i64;
    let mut matches = 0_i64;
    let mut updated = false;
    let mut can_stop = true;

    for output in outputs {
        if let CommandOutput::RunSchedule(report) | CommandOutput::OverallStatistics(report) =
            output
        {
            iterations += report.iterations.len() as i64;
            matches += report
                .num_matches_per_rule
                .values()
                .map(|count| *count as i64)
                .sum::<i64>();
            updated |= report.updated;
            can_stop &= report.can_stop;
        }
    }

    numeric_stats.push(("iterations".to_string(), iterations));
    numeric_stats.push(("matches".to_string(), matches));
    numeric_stats.push(("updated".to_string(), i64::from(updated)));
    numeric_stats.push(("can_stop".to_string(), i64::from(can_stop)));
}

pub fn collect_reports(outputs: &[CommandOutput]) -> Vec<(String, Vec<(String, i64)>)> {
    let mut matches_per_rule = BTreeMap::<String, i64>::new();
    let mut search_us_per_rule = BTreeMap::<String, i64>::new();
    let mut search_us_per_ruleset = BTreeMap::<String, i64>::new();
    let mut merge_us_per_ruleset = BTreeMap::<String, i64>::new();
    let mut rebuild_us_per_ruleset = BTreeMap::<String, i64>::new();

    for output in outputs {
        if let CommandOutput::RunSchedule(report) | CommandOutput::OverallStatistics(report) =
            output
        {
            for (rule, count) in &report.num_matches_per_rule {
                add_entry(&mut matches_per_rule, rule.as_ref(), *count as i64);
            }

            for (rule, duration) in &report.search_and_apply_time_per_rule {
                add_entry(
                    &mut search_us_per_rule,
                    rule.as_ref(),
                    duration.as_micros() as i64,
                );
            }

            for (ruleset, duration) in &report.search_and_apply_time_per_ruleset {
                add_entry(
                    &mut search_us_per_ruleset,
                    ruleset.as_ref(),
                    duration.as_micros() as i64,
                );
            }

            for (ruleset, duration) in &report.merge_time_per_ruleset {
                add_entry(
                    &mut merge_us_per_ruleset,
                    ruleset.as_ref(),
                    duration.as_micros() as i64,
                );
            }

            for (ruleset, duration) in &report.rebuild_time_per_ruleset {
                add_entry(
                    &mut rebuild_us_per_ruleset,
                    ruleset.as_ref(),
                    duration.as_micros() as i64,
                );
            }
        }
    }

    vec![
        (
            "matches_per_rule".to_string(),
            map_entries(matches_per_rule),
        ),
        (
            "search_us_per_rule".to_string(),
            map_entries(search_us_per_rule),
        ),
        (
            "search_us_per_ruleset".to_string(),
            map_entries(search_us_per_ruleset),
        ),
        (
            "merge_us_per_ruleset".to_string(),
            map_entries(merge_us_per_ruleset),
        ),
        (
            "rebuild_us_per_ruleset".to_string(),
            map_entries(rebuild_us_per_ruleset),
        ),
    ]
    .into_iter()
    .filter(|(_, entries)| !entries.is_empty())
    .collect()
}

fn add_entry(map: &mut BTreeMap<String, i64>, key: &str, value: i64) {
    *map.entry(key.to_string()).or_insert(0) += value;
}

fn map_entries(map: BTreeMap<String, i64>) -> Vec<(String, i64)> {
    map.into_iter().collect()
}
