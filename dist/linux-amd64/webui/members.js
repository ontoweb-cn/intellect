/**
 * Members panel: invites, API tokens, OAuth identities.
 */

function membersRegisterUrl() {
    try {
        return new URL('register', document.baseURI || window.location.href).href;
    } catch (e) {
        return '/register';
    }
}

function membersLoginUrl() {
    try {
        return new URL('login', document.baseURI || window.location.href).href;
    } catch (e) {
        return '/login';
    }
}

function membersRenderSignInPrompt(status) {
    let html = '<div class="members-guest-panel">';
    html += '<p class="panel-empty">' + esc(t('members_sign_in_or_register') || 'Sign in or create an account to continue.') + '</p>';
    html += '<div class="members-token-row">';
    html += '<a class="sm-btn provider-card-btn-primary" href="' + esc(membersRegisterUrl()) + '">' + esc(t('members_open_register') || 'Create account') + '</a>';
    html += '<a class="sm-btn" href="' + esc(membersLoginUrl()) + '">' + esc(t('members_open_login') || 'Sign in') + '</a>';
    html += '</div></div>';
    return html;
}

async function loadMembersPanel() {
    const root = document.getElementById('membersPanelRoot');
    if (!root) return;
    const status = typeof fetchMembersStatus === 'function' ? await fetchMembersStatus() : null;
    if (!status || !status.enabled) {
        root.innerHTML = '<p class="panel-empty">' + esc(t('members_disabled') || 'Members are not enabled for this profile.') + '</p>';
        return;
    }
    if (!status.actor_member_id) {
        root.innerHTML = membersRenderSignInPrompt(status);
        return;
    }

    root.innerHTML = '<div class="members-panel-loading">' + esc(t('loading') || 'Loading…') + '</div>';

    const caps = status.capabilities || {};
    let html = '';

    html += '<section class="members-section"><h3 class="members-section-title">' + esc(t('members_password') || 'Account password') + '</h3>';
    html += '<p class="members-hint" id="membersPasswordHint"></p>';
    html += '<p class="members-error" id="membersPasswordError" hidden></p>';
    html += '<form id="membersPasswordForm" class="member-password-form">';
    html += '<label class="member-login-label" id="membersPasswordCurrentLabel" for="membersPasswordCurrent">' + esc(t('member_password_current') || 'Current password') + '</label>';
    html += '<input type="password" id="membersPasswordCurrent" class="input" data-member-password-current autocomplete="current-password">';
    html += '<label class="member-login-label" for="membersPasswordNew">' + esc(t('member_password_new') || 'New password') + '</label>';
    html += '<input type="password" id="membersPasswordNew" class="input" data-member-password-new autocomplete="new-password" required>';
    html += '<label class="member-login-label" for="membersPasswordConfirm">' + esc(t('member_password_confirm') || 'Confirm password') + '</label>';
    html += '<input type="password" id="membersPasswordConfirm" class="input" data-member-password-confirm autocomplete="new-password" required>';
    html += '<div class="member-password-actions"><button type="submit" class="sm-btn provider-card-btn-primary">' + esc(t('member_password_save') || 'Save password') + '</button></div>';
    html += '</form></section>';

    html += '<section class="members-section"><h3 class="members-section-title">' + esc(t('members_identities') || 'Linked accounts') + '</h3>';
    html += '<div id="membersLinkProviders"></div>';
    html += '<div id="membersIdentitiesList"></div></section>';

    html += '<section class="members-section"><h3 class="members-section-title">' + esc(t('members_api_tokens') || 'API tokens') + '</h3>';
    html += '<div class="members-token-row"><input type="text" id="membersTokenLabel" placeholder="' + esc(t('members_token_label') || 'Label') + '" class="input">';
    html += '<button type="button" class="sm-btn" onclick="membersCreateToken()">' + esc(t('members_create_token') || 'Create token') + '</button></div>';
    html += '<div id="membersTokensList"></div></section>';

    if (caps.can_invite) {
        html += '<section class="members-section"><h3 class="members-section-title">' + esc(t('members_invites') || 'Invites') + '</h3>';
        html += '<div class="members-token-row"><input type="text" id="membersInviteMemberId" placeholder="' + esc(t('members_invite_member_id') || 'Reserved member id (optional)') + '" class="input">';
        html += '<button type="button" class="sm-btn" onclick="membersCreateInvite()">' + esc(t('members_create_invite') || 'Create invite') + '</button></div>';
        html += '<pre id="membersInviteCode" class="members-invite-code" hidden></pre></section>';
    }

    if (caps.can_approve_registrations && status.local_registration_requires_approval) {
        html += '<section class="members-section"><h3 class="members-section-title">' + esc(t('members_pending_registrations') || 'Pending registrations') + '</h3>';
        html += '<div id="membersPendingRegistrations"><span class="members-hint">' + esc(t('loading') || 'Loading…') + '</span></div></section>';
    }

    if (status.teams_enabled) {
        html += '<p class="members-hint"><button type="button" class="sm-btn" onclick="switchPanel(\'teams\')">' +
            esc(t('teams_open_panel') || 'Open Teams panel') + ' →</button></p>';
    }

    root.innerHTML = html;
    membersInitPasswordSection(status);
    await membersLoadLinkProviders(status);
    await membersLoadIdentities();
    await membersLoadTokens();
    if (caps.can_approve_registrations && status.local_registration_requires_approval) {
        await membersLoadPendingRegistrations();
    }
}

async function membersLoadLinkProviders(status) {
    const host = document.getElementById('membersLinkProviders');
    if (!host) return;
    if (!status || !status.oauth_enabled) {
        host.innerHTML = '';
        return;
    }
    let providers = status.oauth_providers || [];
    if (!providers.length) {
        try {
            const listed = await api('/api/members/oauth/providers');
            providers = listed.providers || [];
        } catch (e) {
            providers = [];
        }
    }
    let linked = new Set();
    try {
        const data = await api('/api/members/me/identities');
        for (const row of data.identities || []) {
            if (row.provider_id) linked.add(row.provider_id);
        }
    } catch (e) {
        /* ignore */
    }
    const linkable = providers.filter((p) => p.id && !linked.has(p.id));
    if (!linkable.length) {
        host.innerHTML = '<p class="members-hint">' + esc(t('members_all_providers_linked') || 'All configured providers are already linked.') + '</p>';
        return;
    }
    host.innerHTML = '<p class="members-hint" style="margin-bottom:8px">' + esc(t('members_link_provider_hint') || 'Link another sign-in method to this member:') + '</p>';
    host.innerHTML += '<div class="members-link-providers" id="membersLinkProvidersGrid"></div>';
    const row = document.getElementById('membersLinkProvidersGrid');
    if (row && typeof renderMemberOAuthProviders === 'function') {
        renderMemberOAuthProviders(row, linkable, {
            mode: 'link',
            t: t,
            onSelect: function (providerId) {
                void membersLinkProvider(providerId);
            },
        });
        return;
    }
    if (row) {
        for (const p of linkable) {
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'sm-btn';
            btn.textContent = (t('members_link_provider') || 'Link') + ' ' + (p.display_name || p.id);
            btn.onclick = function () { void membersLinkProvider(p.id); };
            row.appendChild(btn);
        }
    }
}

function membersInitPasswordSection(status) {
    const form = document.getElementById('membersPasswordForm');
    const hint = document.getElementById('membersPasswordHint');
    const errEl = document.getElementById('membersPasswordError');
    const currentInput = document.getElementById('membersPasswordCurrent');
    const currentLabel = document.getElementById('membersPasswordCurrentLabel');
    const hasPassword = Boolean(status && status.member_has_password);
    if (hint) {
        hint.textContent = hasPassword
            ? (t('member_password_change_sub') || 'Update your member sign-in password.')
            : (t('member_password_set_sub') || 'Set a password to sign in with member id + password.');
    }
    if (currentInput) {
        currentInput.hidden = !hasPassword;
        currentInput.required = hasPassword;
        if (!hasPassword) currentInput.value = '';
    }
    if (currentLabel) currentLabel.hidden = !hasPassword;
    if (!form || form.dataset.bound) return;
    form.dataset.bound = '1';
    form.addEventListener('submit', function (e) {
        e.preventDefault();
        void (async function () {
            if (errEl) errEl.hidden = true;
            const ok = await submitMemberPasswordChange(form, errEl);
            if (!ok) return;
            toast(t('member_password_saved') || 'Password saved');
            const fresh = typeof fetchMembersStatus === 'function' ? await fetchMembersStatus() : null;
            membersInitPasswordSection(fresh || status);
            if (typeof refreshMemberChrome === 'function') await refreshMemberChrome();
        })();
    });
}

async function membersLinkProvider(providerId) {
    if (!providerId) return;
    try {
        const data = await api('/api/members/me/identities/link', {
            method: 'POST',
            body: JSON.stringify({ provider: providerId, return_to: '/' }),
        });
        if (data.authorize_url) {
            window.location.href = data.authorize_url;
            return;
        }
        toast(t('members_link_failed') || 'Could not start OAuth link');
    } catch (e) {
        toast(e.message || String(e));
    }
}

async function membersLoadIdentities() {
    const host = document.getElementById('membersIdentitiesList');
    if (!host) return;
    try {
        const data = await api('/api/members/me/identities');
        const ids = data.identities || [];
        if (!ids.length) {
            host.innerHTML = '<p class="members-hint">' + esc(t('members_no_identities') || 'No linked OAuth identities.') + '</p>';
            return;
        }
        host.innerHTML = '';
        for (const row of ids) {
            const div = document.createElement('div');
            div.className = 'members-identity-row';
            const label = (row.display_name || row.provider_id || '') + (row.email ? ' · ' + row.email : '');
            const sub = row.provider_id ? esc(row.provider_id) + ' / ' + esc(row.external_id || '') : esc(row.platform || '') + ' / ' + esc(row.external_id || '');
            div.innerHTML =
                '<div class="members-identity-meta"><span class="members-identity-label">' + esc(label || sub) + '</span>' +
                (label ? '<span class="members-identity-sub">' + sub + '</span>' : '') +
                '</div>';
            const pid = row.provider_id || (String(row.platform || '').replace(/^oauth:/, ''));
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'sm-btn provider-card-btn-danger';
            btn.textContent = t('unlink') || 'Unlink';
            btn.onclick = function () {
                void membersUnlinkIdentity(pid, row.external_id);
            };
            div.appendChild(btn);
            host.appendChild(div);
        }
    } catch (e) {
        host.innerHTML = '<p class="members-error">' + esc(e.message) + '</p>';
    }
}

async function membersUnlinkIdentity(providerId, externalId) {
    const enc = encodeURIComponent(providerId) + '/' + encodeURIComponent(externalId);
    await api('/api/members/me/identities/' + enc, { method: 'DELETE' });
    toast(t('members_unlinked') || 'Identity unlinked');
    const status = await fetchMembersStatus();
    await membersLoadLinkProviders(status);
    await membersLoadIdentities();
}

async function membersLoadTokens() {
    const host = document.getElementById('membersTokensList');
    if (!host) return;
    try {
        const data = await api('/api/members/tokens');
        const tokens = data.tokens || [];
        if (!tokens.length) {
            host.innerHTML = '<p class="members-hint">' + esc(t('members_no_tokens') || 'No API tokens.') + '</p>';
            return;
        }
        host.innerHTML = '<ul class="members-token-list"></ul>';
        const ul = host.querySelector('ul');
        for (const tok of tokens) {
            const li = document.createElement('li');
            li.className = 'members-token-item';
            li.innerHTML = '<code>' + esc(tok.id) + '</code> ' + esc(tok.label || '') + ' <span class="oauth-badge ' + (tok.status === 'active' ? 'oauth-connected' : 'oauth-disconnected') + '">' + esc(tok.status) + '</span>';
            if (tok.status === 'active') {
                const btn = document.createElement('button');
                btn.type = 'button';
                btn.className = 'sm-btn';
                btn.textContent = t('revoke') || 'Revoke';
                btn.onclick = function () { void membersRevokeToken(tok.id); };
                li.appendChild(btn);
            }
            ul.appendChild(li);
        }
    } catch (e) {
        host.innerHTML = '<p class="members-error">' + esc(e.message) + '</p>';
    }
}

async function membersCreateToken() {
    const label = (document.getElementById('membersTokenLabel') || {}).value || '';
    const data = await api('/api/members/tokens', { method: 'POST', body: JSON.stringify({ label }) });
    if (data.bearer) {
        toast(t('members_token_created') || 'Token created (copy now): ' + data.bearer);
        try { await copyToClipboard(data.bearer); } catch (e) { /* ignore */ }
    }
    await membersLoadTokens();
}

async function membersRevokeToken(tokenId) {
    await api('/api/members/tokens/' + encodeURIComponent(tokenId), { method: 'DELETE' });
    await membersLoadTokens();
}

async function membersCreateInvite() {
    const mid = (document.getElementById('membersInviteMemberId') || {}).value || '';
    const body = mid ? { member_id: mid } : {};
    const data = await api('/api/members/invites', { method: 'POST', body: JSON.stringify(body) });
    const pre = document.getElementById('membersInviteCode');
    if (pre && data.code) {
        pre.hidden = false;
        pre.textContent = data.code;
        try { await copyToClipboard(data.code); } catch (e) { /* ignore */ }
        toast(t('members_invite_copied') || 'Invite code created (copied)');
    }
}

async function membersLoadPendingRegistrations() {
    const host = document.getElementById('membersPendingRegistrations');
    if (!host) return;
    try {
        const data = await api('/api/members/registrations/pending');
        const rows = data.registrations || [];
        if (!rows.length) {
            host.innerHTML = '<p class="members-hint">' + esc(t('members_pending_registrations_empty') || 'No pending registrations.') + '</p>';
            return;
        }
        host.innerHTML = '';
        for (const row of rows) {
            const div = document.createElement('div');
            div.className = 'members-pending-row';
            const label = (row.display_name || row.id || '').trim();
            div.innerHTML =
                '<div class="members-identity-meta"><span class="members-identity-label">' + esc(label) + '</span>' +
                '<span class="members-identity-sub"><code>' + esc(row.id || '') + '</code></span></div>' +
                '<div class="members-token-row">' +
                '<button type="button" class="sm-btn">' + esc(t('members_approve_registration') || 'Approve') + '</button>' +
                '<button type="button" class="sm-btn">' + esc(t('members_reject_registration') || 'Reject') + '</button>' +
                '</div>';
            const buttons = div.querySelectorAll('button');
            if (buttons[0]) buttons[0].onclick = function () { void membersApproveRegistration(row.id); };
            if (buttons[1]) buttons[1].onclick = function () { void membersRejectRegistration(row.id); };
            host.appendChild(div);
        }
    } catch (e) {
        host.innerHTML = '<p class="members-error">' + esc(e.message) + '</p>';
    }
}

async function membersApproveRegistration(memberId) {
    if (!memberId) return;
    try {
        await api('/api/members/registrations/' + encodeURIComponent(memberId) + '/approve', { method: 'POST', body: '{}' });
        toast(t('members_registration_approved') || 'Registration approved');
        await membersLoadPendingRegistrations();
    } catch (e) {
        toast(e.message || String(e));
    }
}

async function membersRejectRegistration(memberId) {
    if (!memberId) return;
    try {
        await api('/api/members/registrations/' + encodeURIComponent(memberId) + '/reject', { method: 'POST', body: '{}' });
        toast(t('members_registration_rejected') || 'Registration rejected');
        await membersLoadPendingRegistrations();
    } catch (e) {
        toast(e.message || String(e));
    }
}
