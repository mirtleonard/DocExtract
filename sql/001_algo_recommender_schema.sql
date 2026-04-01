create table if not exists skills (
    id bigserial primary key,
    code text not null unique,
    name text not null,
    parent_skill_id bigint references skills(id)
);

create table if not exists problems (
    id bigserial primary key,
    title text not null,
    statement_difficulty numeric(8,4) not null default 0,
    algorithmic_difficulty numeric(8,4) not null default 0,
    difficulty_uncertainty numeric(8,4) not null default 1,
    created_at timestamptz not null default now()
);

create table if not exists problem_skills (
    problem_id bigint not null references problems(id) on delete cascade,
    skill_id bigint not null references skills(id) on delete cascade,
    weight numeric(6,4) not null,
    primary key (problem_id, skill_id)
);

create table if not exists submissions (
    id bigserial primary key,
    user_id bigint not null,
    problem_id bigint not null references problems(id) on delete cascade,
    verdict text not null,
    score numeric(6,4),
    runtime_ms integer,
    memory_kb integer,
    tests_passed integer,
    tests_total integer,
    hint_used boolean not null default false,
    editorial_used boolean not null default false,
    created_at timestamptz not null default now()
);

create table if not exists user_skill_state (
    user_id bigint not null,
    skill_id bigint not null references skills(id) on delete cascade,
    ability numeric(8,4) not null default 0,
    uncertainty numeric(8,4) not null default 1,
    attempts integer not null default 0,
    solves integer not null default 0,
    last_practiced_at timestamptz,
    primary key (user_id, skill_id)
);

create table if not exists user_global_state (
    user_id bigint primary key,
    global_ability numeric(8,4) not null default 0,
    uncertainty numeric(8,4) not null default 1,
    updated_at timestamptz not null default now()
);

create table if not exists user_problem_state (
    user_id bigint not null,
    problem_id bigint not null references problems(id) on delete cascade,
    attempts integer not null default 0,
    solved boolean not null default false,
    first_solved_at timestamptz,
    last_attempt_at timestamptz,
    primary key (user_id, problem_id)
);

create table if not exists problem_rating_state (
    problem_id bigint primary key references problems(id) on delete cascade,
    difficulty numeric(8,4) not null default 0,
    uncertainty numeric(8,4) not null default 1,
    attempts integer not null default 0,
    solves integer not null default 0,
    first_try_solves integer not null default 0,
    median_time_to_solve_sec integer
);

create table if not exists recommendation_cache (
    user_id bigint not null,
    problem_id bigint not null references problems(id) on delete cascade,
    recommendation_score numeric(10,6) not null,
    solve_probability numeric(10,6) not null,
    generated_at timestamptz not null default now(),
    primary key (user_id, problem_id)
);

create index if not exists idx_problem_skills_skill_id on problem_skills(skill_id);
create index if not exists idx_submissions_user_problem_created_at on submissions(user_id, problem_id, created_at desc);
create index if not exists idx_user_skill_state_user_id on user_skill_state(user_id);
create index if not exists idx_user_problem_state_user_id on user_problem_state(user_id);
create index if not exists idx_problem_rating_state_difficulty on problem_rating_state(difficulty);
