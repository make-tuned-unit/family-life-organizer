// Enumerate EVERY model-facing action and its legacy direct-handler entry point.
// Invalid payloads must fail before any database, push or network operation.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const tools = require('../services/conciergeTools');
const routes = tools.definitions().flatMap(d => d.input_schema.properties.action?.enum
  ? d.input_schema.properties.action.enum.map(action => ({ name: d.name, action, handler: tools.operationMetadata(d.name, { action }).handlerName }))
  : [{ name: d.name, handler: d.name }]);

function example(schema) {
  if (schema.enum) return schema.enum.find(x => x !== null);
  const type = Array.isArray(schema.type) ? schema.type.find(t => t !== 'null') : schema.type;
  if (type === 'object') return Object.fromEntries((schema.required || []).map(k => [k, example(schema.properties[k])]));
  if (type === 'array') return [example(schema.items || { type: 'string' })];
  if (type === 'boolean') return true;
  if (type === 'integer' || type === 'number') return 1;
  return 'fixture';
}
const denyContext = new Proxy({}, { get(_, key) { throw new Error(`SIDE EFFECT: accessed ${String(key)}`); } });
for (const route of routes) {
  const impl = tools.TOOLS.find(t => t.name === route.handler);
  const paths = [[route.name, route.action ? { action: route.action } : {}]];
  if (route.action) paths.push([route.handler, {}]);
  test(`${route.name}/${route.action || 'call'}: strict contract on grouped and direct entry`, async () => {
    assert.ok(impl);
    const valid = example(impl.input_schema);
    const samples = [{ ...valid, unexpected_silently_ignored_field: true }];
    if (impl.input_schema.required?.length) samples.push({});
    for (const [field, schema] of Object.entries(impl.input_schema.properties || {})) {
      const types = Array.isArray(schema.type) ? schema.type : [schema.type];
      const wrong = types.includes('object') ? false : { unexpected: true };
      samples.push({ ...valid, [field]: wrong });
      if (schema.enum) samples.push({ ...valid, [field]: '__invalid_enum_value__' });
    }
    for (const [name, selector] of paths) {
      for (const sample of samples) {
        const output = await tools.run(name, denyContext, { ...selector, ...sample });
        assert.equal(output.result.ok, false, `${name}: ${JSON.stringify(sample)}`);
        assert.match(output.result.error, /Invalid fields/);
        assert.equal(output.action, undefined);
      }
    }
    assert.equal(tools.isReadOnly(route.name, { action: route.action }), !impl.write);
  });
}

test('all handlers are covered exactly once by public routes', () => {
  assert.equal(routes.length, tools.TOOLS.length);
  assert.equal(new Set(routes.map(r => r.handler)).size, tools.TOOLS.length);
});
