///|
#deprecated("Use `==` / `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend CellRef with Eq::{not_equal, equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend CellRef with @debug.Debug::{to_repr}

///|
#deprecated("Use `==` / `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Color with Eq::{not_equal, equal}

///|
#deprecated("Use `Hash::hash` instead", skip_current_package=true)
#doc(hidden)
pub extend Color with Hash::{hash, hash_combine}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend Color with @debug.Debug::{to_repr}

///|
#deprecated("Use `==` / `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend DateSystem with Eq::{not_equal, equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend DateSystem with @debug.Debug::{to_repr}

///|
#deprecated("Use `==` / `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend DateTime with Eq::{not_equal, equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend DateTime with @debug.Debug::{to_repr}

///|
#deprecated("Use `==` / `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Duration with Eq::{not_equal, equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend Duration with @debug.Debug::{to_repr}
