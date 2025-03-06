use crate::error_template::{AppError, ErrorTemplate};
use leptos::*;
use leptos_meta::*;
use leptos_router::*;
use leptos_use::{use_interval, UseIntervalReturn};
use serde::{self, Deserialize, Serialize};
use std::cmp::{max, min};

type KEY = usize;

#[cfg(feature = "ssr")]
pub mod ssr {
    use crate::app::{MachineS, MachineState, KEY};
    use itertools::Itertools;
    use serde::{Deserialize, Serialize};
    use std::fs::File;
    use std::io::{Read, Write};
    use std::sync::LazyLock;
    static PATH: LazyLock<String> = LazyLock::new(|| {
        std::env::var("LEPTOS_DB_FILE").unwrap_or("/home/hannses/tmp/esw".to_string())
    });

    #[derive(Serialize, Deserialize)]
    struct MachineSServer {
        state: MachineStateServer,
        name: String,
    }
    impl MachineSServer {
        pub fn new(name: impl ToString) -> Self {
            Self {
                state: MachineStateServer::Empty(),
                name: name.to_string(),
            }
        }
    }

    impl From<&MachineS> for MachineSServer {
        fn from(value: &MachineS) -> Self {
            Self {
                state: value.state.into(),
                name: value.name.clone(),
            }
        }
    }

    impl Into<MachineS> for &MachineSServer {
        fn into(self) -> MachineS {
            MachineS {
                state: self.state.into(),
                name: self.name.clone(),
            }
        }
    }
    #[derive(Serialize, Deserialize, Copy, Clone)]
    enum MachineStateServer {
        ///time when done
        Full(u64),
        Empty(),
        Broken(),
    }

    impl From<MachineState> for MachineStateServer {
        fn from(value: MachineState) -> Self {
            match value {
                MachineState::DoneFull(t) => Self::Full(t),
                MachineState::Doing(t) => Self::Full(t),
                MachineState::DoneEmpty() => Self::Empty(),
                MachineState::Broken() => Self::Broken(),
            }
        }
    }

    impl Into<MachineState> for MachineStateServer {
        fn into(self) -> MachineState {
            use std::time::{SystemTime, UNIX_EPOCH};
            let current = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs();
            match self {
                MachineStateServer::Full(t) => {
                    if t > current {
                        MachineState::Doing(t)
                    } else {
                        MachineState::DoneFull(t)
                    }
                }
                MachineStateServer::Empty() => MachineState::DoneEmpty(),
                MachineStateServer::Broken() => MachineState::Broken(),
            }
        }
    }

    pub fn read_file() -> Vec<MachineS> {
        let default_machines = vec![
            MachineSServer::new("Waschmaschine 1"),
            MachineSServer::new("Waschmaschine 2"),
            MachineSServer::new("Waschmaschine 3"),
            MachineSServer::new("Trockner 4"),
            MachineSServer::new("Trockner 5"),
        ];
        println!("DB-PATH: {}", PATH.clone());
        let mut file = File::open(PATH.clone()).unwrap_or_else(|_| {
            let f = File::create_new(PATH.clone()).expect("could neither open nor create file");
            f
        });
        let mut contents = String::new();
        file.read_to_string(&mut contents)
            .expect("failed to read file");
        ron::from_str(&contents)
            .unwrap_or(default_machines)
            .iter()
            .map_into()
            .collect()
    }

    pub fn write_file(contents: &Vec<MachineS>) -> Result<(), ()> {
        let mut file = File::options()
            .write(true)
            .truncate(true)
            .open(PATH.clone())
            .unwrap_or_else(|_| {
                let f = File::create_new(PATH.clone()).expect("could neither open nor create file");
                f
            });
        let contents = contents
            .iter()
            .map(|v| -> MachineSServer { v.into() })
            .collect_vec();
        let string = ron::to_string(&contents).map_err(|_| ())?;
        file.write_all(string.as_bytes())
            .expect("failed to write to file");
        Ok(())
    }

    pub fn set_machine_state(s: MachineState, idx: KEY) -> Result<(), ()> {
        let mut old = read_file();
        old[idx].state = s;
        write_file(&old)
    }
}

#[component]
pub fn App() -> impl IntoView {
    // Provides context that manages stylesheets, titles, meta tags, etc.
    provide_meta_context();

    view! {


        // injects a stylesheet into the document <head>
        // id=leptos means cargo-leptos will hot-reload this stylesheet
        <Stylesheet id="leptos" href="/pkg/esw-machines.css"/>

        // sets the document title
        <Title text="ESW Waschmaschinen"/>

        // content for this welcome page
        <Router fallback=|| {
            let mut outside_errors = Errors::default();
            outside_errors.insert_with_default_key(AppError::NotFound);
            view! {
                <ErrorTemplate outside_errors/>
            }
            .into_view()
        }>
            <main>
                <Routes>
                    <Route path="/" view=HomePage/>
                </Routes>
            </main>
        </Router>
    }
}

/// Renders the home page of your application.
#[component]
fn HomePage() -> impl IntoView {
    view! {
    <div class="centered">
     <div class="responsive-size">

      <div class="container">
         <h1 class="heading">ESW Wäscheraum</h1>
      </div>
      <ul class="machines" role="list">
      <Await
        future =|| get_machines()
        let:data
      >
      {
          data.to_owned().unwrap_or_default().into_iter().enumerate().map(|(idx, m)| view! {

      <Machine name={m.name} idx={idx} state={m.state}/>
          }).collect_view()
     }
      </Await>
      </ul>
     </div>
    </div>
     }
}
#[server(getMachines)]
pub async fn get_machines() -> Result<Vec<MachineS>, ServerFnError> {
    Ok(ssr::read_file())
}

#[derive(Serialize, Deserialize, Clone)]
pub struct MachineS {
    state: MachineState,
    name: String,
}

#[derive(Copy, Clone, Serialize, Deserialize)]
pub enum MachineState {
    DoneFull(u64),
    Doing(u64),
    DoneEmpty(),
    Broken(),
}

// impl IntoView for MachineState {
// fn into_view(self) -> View {

#[component]
fn MachineStateV(state: MachineState) -> impl IntoView {
    use web_time::{SystemTime, UNIX_EPOCH};
    let (text, bg, shown, t) = match state {
        MachineState::DoneFull(t) => ("Fertig", "bg_orange", false, t),
        MachineState::Doing(t) => ("Läuft", "bg_red", true, t),
        MachineState::DoneEmpty() => ("Leer", "bg_green", false, 0),
        MachineState::Broken() => ("Defekt", "bg_red", false, 0),
    };
    let hidden_class = if shown { "" } else { " hidden" };
    let UseIntervalReturn { counter, .. } = use_interval(1000);
    let time = move || {
        let current = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let secs = max(0, t as i128 - current as i128);
        let _ = counter.get(); //updates every second
        format!(
            "{:02}:{:02}",
            secs / 3600,
            min(59, ((secs.abs() % 3600) as f64 / 60.0_f64).ceil() as i128) //only show minus on hours
                                                                            //never show sth like: 0:60 humans are dumb...
        )
    };
    view! {
        <dl class= "machine_mid_state">
    <dd class= "machine_mid_state_holder">
      <span class="machine_mid_state_state {bg}">
        {text}
      </span>
    </dd>
         <dd class= "machine_mid_state_holder">
          <div class="machine_mid_state_time{hidden_class}" >
          {time}
          </div>
         </dd>
        </dl>
    }
}

#[component]
fn Machine(name: String, idx: KEY, state: MachineState) -> impl IntoView {
    let bg = match state {
        MachineState::DoneFull(_) => "bg_orange",
        MachineState::Doing(_) => "bg_red",
        MachineState::DoneEmpty() => "bg_green",
        MachineState::Broken() => "bg_red",
    };
    view! {
        <li class="machine rounding">
          <div class="machine_color_band {bg}"> </div>
          <div class="machine_mid">
            <h3 class= "machine_mid_name"> {name} </h3>
            <MachineStateV state={state}/>
          </div>
          <div>
      <div class="machine_bottom_to_empty_div">
              {
                  match state {
                     MachineState::DoneFull(t) => view!{ <MachineToEmpty idx={idx} time={t}/>},
                     MachineState::Doing(t) => view! {<MachineTime idx={idx} time={t}/>},
                     MachineState::DoneEmpty() => view!{ <MachineFill idx={idx}/>},
                     MachineState::Broken() => view!{<MachineBroken idx={idx}/>}
                  }
              }
          </div>
      </div>

        </li>
    }
}

#[server(emptyMachine)]
pub async fn empty_machine(idx: KEY) -> Result<(), ServerFnError> {
    println!("emptied: {idx}");
    ssr::set_machine_state(MachineState::DoneEmpty(), idx)
        .map_err(|_| ServerFnError::new("oops"))?;
    leptos_axum::redirect("/");
    Ok(())
}

#[component]
fn MachineToEmpty(idx: KEY, time: u64) -> impl IntoView {
    let empty_machine = create_server_action::<emptyMachine>();
    let onclick = "this.form.submit();";
    view! {
        <ActionForm action=empty_machine class="machine_bottom_to_empty_form">
          <button type="submit" class="machine_bottom_to_empty bg_grey" onclick={onclick}>
            Maschine geleert
          </button>
          <input type="hidden" name="idx" value={idx}/>
        </ActionForm>
    }
}

#[server(MachineBroken)]
pub async fn repair_machine(idx: KEY) -> Result<(), ServerFnError> {
    println!("repaired: {idx}");
    ssr::set_machine_state(MachineState::DoneEmpty(), idx)
        .map_err(|_| ServerFnError::new("oops"))?;
    leptos_axum::redirect("/");
    Ok(())
}

#[component]
fn MachineBroken(idx: KEY) -> impl IntoView {
    let repair_machine = create_server_action::<MachineBroken>();
    let onclick = "this.form.submit();";
    view! {
        <ActionForm action=repair_machine class="machine_bottom_to_empty_form">
          <button type="submit" class="machine_bottom_to_repair bg_red" onclick={onclick}>
            Maschine repariert
          </button>
          <input type="hidden" name="idx" value={idx}/>
        </ActionForm>
    }
}
#[server(fillMachine)]
pub async fn fill_machine(idx: KEY, time: u16) -> Result<(), ServerFnError> {
    if time == 0 {
        println!("broke: {idx}");
        ssr::set_machine_state(MachineState::Broken(), idx)
            .map_err(|_| ServerFnError::new("oops"))?;
        return Ok(());
    }
    use std::time::{SystemTime, UNIX_EPOCH};
    println!("filled: {idx} for {time}");
    let current = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| ServerFnError::new("oops"))?
        .as_secs();
    ssr::set_machine_state(MachineState::Doing(current + (time * 60) as u64), idx)
        .map_err(|_| ServerFnError::new("oops"))
}

#[component]
fn MachineFill(idx: KEY) -> impl IntoView {
    let options = (vec![30, 60, 90, 120, 150, 180, 210])
        .into_iter()
        .map(|value| {
            let hours = value / 60;
            let minutes = format!("{:02}", value % 60);
            view! {
                <option value="{value}">{hours}:{minutes}</option>
            }
        })
        .collect_view();
    let fill_machine = create_server_action::<fillMachine>();
    let onchange = "this.form.submit();";
    view! {

        <ActionForm action=fill_machine class="machine_bottom_to_empty_form">
          <select
            class="machine_bottom_to_empty bg_grey"
            name="time"
            onchange={onchange}
          >
          <option selected disabled>Dauer wählen</option>
          {options}
          <option value="0">Maschine Defekt</option>
          </select>
          <input type="hidden" name="idx" value={idx}/>
        </ActionForm>
    }
}

#[server(cancleMachine)]
pub async fn cancle_machine(idx: KEY) -> Result<(), ServerFnError> {
    use std::time::{SystemTime, UNIX_EPOCH};
    println!("cancle: {idx}");
    let current = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| ServerFnError::new("oops"))?
        .as_secs();
    ssr::set_machine_state(MachineState::DoneFull(current - 1), idx)
        .map_err(|_| ServerFnError::new("oops"))?;
    leptos_axum::redirect("/");
    Ok(())
}

#[component]
fn MachineTime(idx: KEY, time: u64) -> impl IntoView {
    let cancle_machine = create_server_action::<cancleMachine>();
    let onclick = "this.form.submit();";
    view! {
        <ActionForm action=cancle_machine class="machine_bottom_to_empty_form">
          <button type="submit" class="machine_bottom_to_empty bg_grey" onclick={onclick}>
            Abbrechen
          </button>
          <input type="hidden" name="idx" value={idx}/>
        </ActionForm>
    }
}
