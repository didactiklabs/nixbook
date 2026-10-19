package core

import (
	"errors"
	"maps"
	"slices"
)

// Kind is a change's op ("op", or "action").
func Kind(op map[string]any) string {
	k, _ := op["op"].(string)
	if k == "" {
		k, _ = op["action"].(string)
	}
	return k
}

// Clone is a shallow copy of a change, to rewrite its ids.
func Clone(op map[string]any) map[string]any { return maps.Clone(op) }

// Result is one change's outcome.
type Result struct {
	OK     bool   `json:"ok"`
	Result any    `json:"result,omitempty"`
	Error  string `json:"error,omitempty"`
}

// Ops is a request's changes: {op…} or {ops: […]}, 1 to max of them.
func Ops(request any, max int) ([]any, error) {
	var ops []any
	if m, ok := request.(map[string]any); ok {
		if v, has := m["ops"]; has {
			ops, _ = v.([]any)
		} else {
			ops = []any{m}
		}
	}
	if len(ops) == 0 || len(ops) > max {
		return nil, Errorf("`ops` must be a list of 1 to %d changes", max)
	}
	return ops, nil
}

// RunOps runs each change on its own, in order; authErr is the first
// sign-in failure when no change went through (exit 2).
func RunOps(ops []any, apply func(map[string]any) (any, error)) (results []Result, authErr error) {
	results = make([]Result, 0, len(ops))
	for _, o := range ops {
		op, ok := o.(map[string]any)
		var res any
		var err error
		if ok {
			res, err = apply(op)
		} else {
			err = Errorf("each change must be an object")
		}
		var auth *AuthError
		if errors.As(err, &auth) && authErr == nil {
			authErr = err
		}
		if err != nil {
			results = append(results, Result{Error: err.Error()})
		} else {
			results = append(results, Result{OK: true, Result: res})
		}
	}
	if slices.ContainsFunc(results, func(r Result) bool { return r.OK }) {
		authErr = nil
	}
	return results, authErr
}
