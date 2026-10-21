// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

// E0079: trait methods are no longer promoted to regular methods implicitly.

///|
pub extend TypedName with Eq::{not_equal, equal}

///|
pub extend TypedName with @debug.Debug::{to_repr}

///|
pub extend Term with Eq::{not_equal, equal}

///|
pub extend Term with @debug.Debug::{to_repr}

///|
pub extend PAtom with Eq::{not_equal, equal}

///|
pub extend PAtom with @debug.Debug::{to_repr}

///|
pub extend Formula with Eq::{not_equal, equal}

///|
pub extend Formula with @debug.Debug::{to_repr}

///|
pub extend Effect with Eq::{not_equal, equal}

///|
pub extend Effect with @debug.Debug::{to_repr}

///|
pub extend TypeDecl with Eq::{not_equal, equal}

///|
pub extend TypeDecl with @debug.Debug::{to_repr}

///|
pub extend Predicate with Eq::{not_equal, equal}

///|
pub extend Predicate with @debug.Debug::{to_repr}

///|
pub extend FunctionDecl with Eq::{not_equal, equal}

///|
pub extend FunctionDecl with @debug.Debug::{to_repr}

///|
pub extend Action with Eq::{not_equal, equal}

///|
pub extend Action with @debug.Debug::{to_repr}

///|
pub extend Domain with Eq::{not_equal, equal}

///|
pub extend Domain with @debug.Debug::{to_repr}

///|
pub extend InitElem with Eq::{not_equal, equal}

///|
pub extend InitElem with @debug.Debug::{to_repr}

///|
pub extend Metric with Eq::{not_equal, equal}

///|
pub extend Metric with @debug.Debug::{to_repr}

///|
pub extend Problem with Eq::{not_equal, equal}

///|
pub extend Problem with @debug.Debug::{to_repr}

///|
pub extend Position with Eq::{not_equal, equal}

///|
pub extend Position with @debug.Debug::{to_repr}

///|
pub extend PddlErrorData with Eq::{not_equal, equal}

///|
pub extend PddlErrorData with @debug.Debug::{to_repr}

///|
pub extend PddlError with @debug.Debug::{to_repr}

///|
pub extend PddlError with Show::{to_string, output}

///|
pub extend Literal with Eq::{not_equal, equal}

///|
pub extend Literal with @debug.Debug::{to_repr}

///|
pub extend GroundAtom with Eq::{not_equal, equal}

///|
pub extend GroundAtom with @debug.Debug::{to_repr}

///|
pub extend GroundEffect with Eq::{not_equal, equal}

///|
pub extend GroundEffect with @debug.Debug::{to_repr}

///|
pub extend GroundAction with Eq::{not_equal, equal}

///|
pub extend GroundAction with @debug.Debug::{to_repr}

///|
pub extend State with @debug.Debug::{to_repr}

///|
pub extend GroundProblem with @debug.Debug::{to_repr}

///|
pub extend HeuristicKind with Eq::{not_equal, equal}

///|
pub extend HeuristicKind with @debug.Debug::{to_repr}

///|
pub extend SearchAlgorithm with Eq::{not_equal, equal}

///|
pub extend SearchAlgorithm with @debug.Debug::{to_repr}

///|
pub extend SearchStatus with Eq::{not_equal, equal}

///|
pub extend SearchStatus with @debug.Debug::{to_repr}

///|
pub extend SearchResult with @debug.Debug::{to_repr}

///|
pub extend ValidationIssueKind with Eq::{not_equal, equal}

///|
pub extend ValidationIssueKind with @debug.Debug::{to_repr}

///|
pub extend ValidationIssue with @debug.Debug::{to_repr}

///|
pub extend ValidationReport with @debug.Debug::{to_repr}
