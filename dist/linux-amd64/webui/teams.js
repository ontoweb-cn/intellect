/**
 * Teams panel — join, active team, admin approve/create.
 */

async function loadTeamsPanel() {
    const root = document.getElementById('teamsPanelRoot');
    if (!root) return;
    const status = typeof fetchMembersStatus === 'function' ? await fetchMembersStatus() : null;
    if (!status || !status.enabled) {
        root.innerHTML = '<p class="panel-empty">' + esc(t('teams_disabled_members') || 'Enable members in config.yaml first.') + '</p>';
        return;
    }
    if (!status.teams_enabled) {
        root.innerHTML = '<p class="panel-empty">' + esc(t('teams_disabled_teams') || 'Enable members.teams in config.yaml.') + '</p>';
        return;
    }
    if (!status.actor_member_id) {
        root.innerHTML = '<p class="panel-empty">' + esc(t('teams_sign_in_first') || 'Sign in to manage teams.') + '</p>';
        return;
    }

    root.innerHTML = '<div class="members-panel-loading">' + esc(t('loading') || 'Loading…') + '</div>';

    let me;
    try {
        me = await api('/api/members/me/teams');
    } catch (e) {
        root.innerHTML = '<p class="members-error">' + esc(e.message) + '</p>';
        return;
    }

    const teams = me.teams || [];
    const caps = status.capabilities || {};
    let html = '';

    if (me.requires_team_selection && !me.active_team_id && typeof getWebuiActiveTeamId === 'function' && !getWebuiActiveTeamId()) {
        html += '<div class="teams-banner">' + esc(t('teams_multi_banner') || 'Select an active team from the account menu.') + '</div>';
    }

    html += '<section class="members-section"><h3 class="members-section-title">' + esc(t('teams_my_teams') || 'My teams') + '</h3>';
    if (!teams.length) {
        html += '<p class="members-hint">' + esc(t('teams_no_memberships') || 'No team memberships yet.') + '</p>';
    } else {
        html += '<ul class="teams-action-list">';
        for (const tm of teams) {
            const active = (me.active_team_id || (typeof getWebuiActiveTeamId === 'function' ? getWebuiActiveTeamId() : '')) === tm.id;
            html += '<li class="teams-action-row">';
            html += '<div><span class="font-mono">' + esc(tm.id) + '</span>';
            if (tm.display_name) html += ' <span class="teams-muted">— ' + esc(tm.display_name) + '</span>';
            html += ' <span class="oauth-badge ' + (tm.status === 'active' ? 'oauth-connected' : 'oauth-disconnected') + '">' + esc(tm.status) + '</span></div>';
            if (tm.status === 'active') {
                html += '<button type="button" class="sm-btn' + (active ? ' provider-card-btn-primary' : '') + '" data-team-use="' + esc(tm.id) + '">' +
                    esc(active ? (t('teams_active') || 'Active') : (t('teams_use') || 'Use')) + '</button>';
            }
            html += '</li>';
        }
        html += '</ul>';
    }
    html += '</section>';

    html += '<section class="members-section"><h3 class="members-section-title">' + esc(t('teams_join') || 'Join a team') + '</h3>';
    html += '<div class="members-token-row"><input type="text" id="teamsJoinId" class="input" placeholder="' + esc(t('members_team_id') || 'team id') + '">';
    html += '<button type="button" class="sm-btn" onclick="teamsJoinTeam()">' + esc(t('members_join_team') || 'Request join') + '</button></div></section>';

    if (caps.can_create_team) {
        html += '<section class="members-section"><h3 class="members-section-title">' + esc(t('teams_create') || 'Create team') + '</h3>';
        html += '<div class="members-token-row"><input type="text" id="teamsNewId" class="input" placeholder="' + esc(t('members_team_id') || 'team id') + '">';
        html += '<input type="text" id="teamsNewName" class="input" placeholder="' + esc(t('teams_display_name') || 'Display name') + '">';
        html += '<button type="button" class="sm-btn" onclick="teamsCreateTeam()">' + esc(t('create') || 'Create') + '</button></div></section>';
    }

    if (caps.profile_admin) {
        html += '<section class="members-section"><h3 class="members-section-title">' + esc(t('teams_admin') || 'Admin') + '</h3>';
        html += '<div id="teamsAdminPending"></div></section>';
    }

    root.innerHTML = html;

    root.querySelectorAll('button[data-team-use]').forEach(function (btn) {
        btn.addEventListener('click', function () {
            const teamId = btn.getAttribute('data-team-use');
            if (teamId) void teamsUseTeam(teamId);
        });
    });

    if (caps.profile_admin) {
        await teamsLoadAdminPending();
    }
}

async function teamsUseTeam(teamId) {
    if (typeof setActiveTeam === 'function') {
        await setActiveTeam(teamId, { silent: true });
    }
    if (typeof showToast === 'function') {
        showToast(t('teams_active_set') || 'Active team updated');
    } else if (typeof toast === 'function') {
        toast(t('teams_active_set') || 'Active team updated');
    }
    await loadTeamsPanel();
}

async function teamsJoinTeam() {
    const tid = (document.getElementById('teamsJoinId') || {}).value || '';
    if (!tid) return;
    await api('/api/teams/' + encodeURIComponent(tid) + '/join', { method: 'POST', body: '{}' });
    toast(t('members_join_requested') || 'Join requested');
    await loadTeamsPanel();
}

async function teamsCreateTeam() {
    const tid = (document.getElementById('teamsNewId') || {}).value || '';
    const name = (document.getElementById('teamsNewName') || {}).value || '';
    if (!tid) return;
    await api('/api/teams', {
        method: 'POST',
        body: JSON.stringify({ team_id: tid, display_name: name || undefined }),
    });
    toast(t('teams_created') || 'Team created');
    await loadTeamsPanel();
}

async function teamsLoadAdminPending() {
    const host = document.getElementById('teamsAdminPending');
    if (!host) return;
    try {
        const { teams } = await api('/api/teams?scope=all');
        const details = await Promise.all((teams || []).map((t) => api('/api/teams/' + encodeURIComponent(t.id))));
        const blocks = details.filter((d) => d.can_approve && (d.pending || []).length > 0);
        if (!blocks.length) {
            host.innerHTML = '<p class="members-hint">' + esc(t('teams_no_pending') || 'No pending join requests.') + '</p>';
            return;
        }
        host.innerHTML = '';
        for (const block of blocks) {
            const sec = document.createElement('div');
            sec.className = 'teams-pending-block';
            sec.innerHTML = '<div class="teams-pending-title font-mono">' + esc(block.team.id) + '</div>';
            const ul = document.createElement('ul');
            ul.className = 'teams-pending-list';
            for (const p of block.pending) {
                const li = document.createElement('li');
                li.className = 'teams-pending-row';
                const mid = p.member_id || p.id || '';
                li.innerHTML = '<span class="font-mono">' + esc(mid) + '</span>';
                const approve = document.createElement('button');
                approve.type = 'button';
                approve.className = 'sm-btn';
                approve.textContent = t('teams_approve') || 'Approve';
                approve.onclick = function () { void teamsApprove(block.team.id, mid); };
                const reject = document.createElement('button');
                reject.type = 'button';
                reject.className = 'sm-btn provider-card-btn-danger';
                reject.textContent = t('teams_reject') || 'Reject';
                reject.onclick = function () { void teamsReject(block.team.id, mid); };
                li.appendChild(approve);
                li.appendChild(reject);
                ul.appendChild(li);
            }
            sec.appendChild(ul);
            host.appendChild(sec);
        }
    } catch (e) {
        host.innerHTML = '<p class="members-error">' + esc(e.message) + '</p>';
    }
}

async function teamsApprove(teamId, memberId) {
    await api('/api/teams/' + encodeURIComponent(teamId) + '/approve', {
        method: 'POST',
        body: JSON.stringify({ member_id: memberId }),
    });
    toast(t('teams_approved') || 'Approved');
    await teamsLoadAdminPending();
    await loadTeamsPanel();
}

async function teamsReject(teamId, memberId) {
    await api('/api/teams/' + encodeURIComponent(teamId) + '/reject', {
        method: 'POST',
        body: JSON.stringify({ member_id: memberId }),
    });
    toast(t('teams_rejected') || 'Rejected');
    await teamsLoadAdminPending();
}
