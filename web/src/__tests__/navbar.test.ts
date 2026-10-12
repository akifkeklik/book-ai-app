import test from 'node:test';
import assert from 'node:assert/strict';

interface NavLinksState {
  showCatalog: boolean;
  showAiDiscovery: boolean;
  showLibrary: boolean;
  showSignOut: boolean;
  showAuthButtons: boolean;
}

function resolveNavbarLinks(user: { id: string } | null, loading: boolean): NavLinksState {
  return {
    showCatalog: true,
    showAiDiscovery: true,
    showLibrary: !loading && user !== null,
    showSignOut: !loading && user !== null,
    showAuthButtons: !loading && user === null,
  };
}

test('Navbar state: unauthenticated user sees public links, login, signup, and NOT library', () => {
  const state = resolveNavbarLinks(null, false);

  assert.equal(state.showCatalog, true);
  assert.equal(state.showAiDiscovery, true);
  assert.equal(state.showAuthButtons, true);
  assert.equal(state.showLibrary, false);
  assert.equal(state.showSignOut, false);
});

test('Navbar state: authenticated user sees Library link, Sign Out, and NOT login/signup', () => {
  const state = resolveNavbarLinks({ id: 'user-456' }, false);

  assert.equal(state.showCatalog, true);
  assert.equal(state.showAiDiscovery, true);
  assert.equal(state.showLibrary, true);
  assert.equal(state.showSignOut, true);
  assert.equal(state.showAuthButtons, false);
});

test('Navbar state: loading state hides auth-specific buttons to prevent UI flashing', () => {
  const state = resolveNavbarLinks(null, true);

  assert.equal(state.showCatalog, true);
  assert.equal(state.showAiDiscovery, true);
  assert.equal(state.showLibrary, false);
  assert.equal(state.showSignOut, false);
  assert.equal(state.showAuthButtons, false);
});
