import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";

export default function App() {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setLoading(false);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => {
      setSession(s);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  if (loading) return <main><p>Loading</p></main>;
  return session ? <Notes session={session} /> : <SignIn />;
}

function SignIn() {
  const [error, setError] = useState("");

  async function signInWithGoogle() {
    setError("");
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: window.location.origin },
    });
    if (error) setError(error.message);
  }

  return (
    <main>
      <h1>Private notes</h1>
      <p>Sign in to see your notes. Only you can read or change them.</p>
      <button onClick={signInWithGoogle}>Continue with Google</button>
      {error && <p role="alert" className="error">{error}</p>}
    </main>
  );
}

function Notes({ session }) {
  const [notes, setNotes] = useState([]);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [editingId, setEditingId] = useState(null);
  const [error, setError] = useState("");

  async function load() {
    // No user_id filter on purpose: RLS returns only this user's rows.
    const { data, error } = await supabase
      .from("notes")
      .select("id, title, body, created_at")
      .order("created_at", { ascending: false });
    if (error) setError(error.message);
    else setNotes(data);
  }

  useEffect(() => {
    load();
  }, []);

  async function save(e) {
    e.preventDefault();
    setError("");
    if (!title.trim()) return;

    // user_id is filled by the column default auth.uid(), never by the client.
    const query = editingId
      ? supabase.from("notes").update({ title, body }).eq("id", editingId)
      : supabase.from("notes").insert({ title, body });

    const { error } = await query;
    if (error) return setError(error.message);

    setTitle("");
    setBody("");
    setEditingId(null);
    load();
  }

  function startEdit(note) {
    setEditingId(note.id);
    setTitle(note.title);
    setBody(note.body);
  }

  async function remove(id) {
    setError("");
    const { error } = await supabase.from("notes").delete().eq("id", id);
    if (error) setError(error.message);
    else load();
  }

  return (
    <main>
      <header>
        <h1>Your notes</h1>
        <div>
          <span>{session.user.email}</span>
          <button className="secondary" onClick={() => supabase.auth.signOut()}>
            Sign out
          </button>
        </div>
      </header>

      <form onSubmit={save}>
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Title"
          aria-label="Title"
        />
        <textarea
          value={body}
          onChange={(e) => setBody(e.target.value)}
          placeholder="Write something"
          aria-label="Body"
          rows={3}
        />
        <div className="row">
          <button type="submit">{editingId ? "Save changes" : "Add note"}</button>
          {editingId && (
            <button
              type="button"
              className="secondary"
              onClick={() => {
                setEditingId(null);
                setTitle("");
                setBody("");
              }}
            >
              Cancel
            </button>
          )}
        </div>
      </form>

      {error && <p role="alert" className="error">{error}</p>}

      {notes.length === 0 ? (
        <p>No notes yet. Add your first one above.</p>
      ) : (
        <ul>
          {notes.map((n) => (
            <li key={n.id}>
              <h2>{n.title}</h2>
              <p>{n.body}</p>
              <div className="row">
                <button className="secondary" onClick={() => startEdit(n)}>Edit</button>
                <button className="secondary" onClick={() => remove(n.id)}>Delete</button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
