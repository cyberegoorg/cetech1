#include "../libs/imgui_node_editor.h"

namespace ed = ax::NodeEditor;

extern "C"
{
    //
    // Editor
    //
    ed::EditorContext *zine_CreateEditor(ed::Config *cfg)
    {
        return ed::CreateEditor(cfg);
    }

    void zine_DestroyEditor(ed::EditorContext *editor)
    {
        return ed::DestroyEditor(editor);
    }

    void zine_SetCurrentEditor(ed::EditorContext *editor)
    {
        return ed::SetCurrentEditor(editor);
    }

    void zine_Begin(const char *id, const float size[2])
    {
        ed::Begin(id, ImVec2(size[0], size[1]));
    }

    void zine_End()
    {
        ed::End();
    }

    bool zine_ShowBackgroundContextMenu()
    {
        return ed::ShowBackgroundContextMenu();
    }

    bool zine_ShowNodeContextMenu(ed::NodeId *id)
    {
        return ed::ShowNodeContextMenu(id);
    }

    bool zine_ShowLinkContextMenu(ed::LinkId *id)
    {
        return ed::ShowLinkContextMenu(id);
    }

    bool zine_ShowPinContextMenu(ed::PinId *id)
    {
        return ed::ShowPinContextMenu(id);
    }

    void zine_Suspend()
    {
        ed::Suspend();
    }

    void zine_Resume()
    {
        ed::Resume();
    }

    void zine_NavigateToContent(float duration)
    {
        ed::NavigateToContent(duration);
    }

    void zine_NavigateToSelection(bool zoomIn, float duration)
    {
        ed::NavigateToSelection(zoomIn, duration);
    }

    void zine_SelectNode(ed::NodeId nodeId, bool append)
    {
        ed::SelectNode(nodeId, append);
    }

    void zine_SelectLink(ed::LinkId linkId, bool append)
    {
        ed::SelectLink(linkId, append);
    }

    //
    // Node
    //
    void zine_BeginNode(ed::NodeId id)
    {
        ed::BeginNode(id);
    }

    void zine_EndNode()
    {
        ed::EndNode();
    }

    void zine_SetNodePosition(ed::NodeId id, const float pos[2])
    {
        ed::SetNodePosition(id, ImVec2(pos[0], pos[1]));
    }

    void zine_getNodePosition(ed::NodeId id, float *pos)
    {
        auto node_pos = ed::GetNodePosition(id);
        pos[0] = node_pos.x;
        pos[1] = node_pos.y;
    }

    void zine_getNodeSize(ed::NodeId id, float *size)
    {
        auto node_size = ed::GetNodeSize(id);
        size[0] = node_size.x;
        size[1] = node_size.y;
    }

    bool zine_DeleteNode(ed::NodeId id)
    {
        return ed::DeleteNode(id);
    }

    //
    // Pin
    //
    void zine_BeginPin(ed::PinId id, ed::PinKind kind)
    {
        ed::BeginPin(id, kind);
    }

    void zine_EndPin()
    {
        ed::EndPin();
    }

    bool zine_PinHadAnyLinks(ed::PinId pinId)
    {
        return ed::PinHadAnyLinks(pinId);
    }

    //
    // Link
    //
    bool zine_Link(ed::LinkId id, ed::PinId startPinId, ed::PinId endPinId, const float color[4], float thickness)
    {
        return ed::Link(id, startPinId, endPinId, ImVec4(color[0], color[1], color[2], color[3]), thickness);
    }

    bool zine_DeleteLink(ed::LinkId id)
    {
        return ed::DeleteLink(id);
    }

    int zine_BreakPinLinks(ed::PinId id)
    {
        return ed::BreakLinks(id);
    }

    // Groups
    void zine_Group(const float size[2])
    {
        ed::Group(ImVec2(size[0], size[1]));
    }

    // Created
    bool zine_BeginCreate()
    {
        return ed::BeginCreate();
    }

    void zine_EndCreate()
    {
        ed::EndCreate();
    }

    bool zine_QueryNewLink(ed::PinId *startId, ed::PinId *endId)
    {
        return ed::QueryNewLink(startId, endId);
    }

    bool zine_AcceptNewItem(const float color[4], float thickness)
    {
        return ed::AcceptNewItem(ImVec4(color[0], color[1], color[2], color[3]), thickness);
    }

    void zine_RejectNewItem(const float color[4], float thickness)
    {
        return ed::RejectNewItem(ImVec4(color[0], color[1], color[2], color[3]), thickness);
    }

    // Delete
    bool zine_BeginDelete()
    {
        return ed::BeginDelete();
    }

    void zine_EndDelete()
    {
        ed::EndDelete();
    }

    bool zine_QueryDeletedLink(ed::LinkId *linkId, ed::PinId *startId, ed::PinId *endId)
    {
        return ed::QueryDeletedLink(linkId, startId, endId);
    }

    bool zine_QueryDeletedNode(ed::NodeId *nodeId)
    {
        return ed::QueryDeletedNode(nodeId);
    }

    bool zine_AcceptDeletedItem(bool deleteDependencies)
    {
        return ed::AcceptDeletedItem(deleteDependencies);
    }

    void zine_RejectDeletedItem()
    {
        ed::RejectDeletedItem();
    }

    // Style
    ax::NodeEditor::Style zine_GetStyle()
    {
        return ed::GetStyle();
    }

    const char *zine_GetStyleColorName(ed::StyleColor colorIndex)
    {
        return ed::GetStyleColorName(colorIndex);
    }

    void zine_PushStyleColor(ed::StyleColor colorIndex, const ImVec4 *color)
    {
        ed::PushStyleColor(colorIndex, *color);
    }

    void zine_PopStyleColor(int count)
    {
        ed::PopStyleColor(count);
    }

    void zine_PushStyleVarF(ed::StyleVar varIndex, float value)
    {
        ed::PushStyleVar(varIndex, value);
    }

    void zine_PushStyleVar2f(ed::StyleVar varIndex, const ImVec2 *value)
    {
        ed::PushStyleVar(varIndex, *value);
    }

    void zine_PushStyleVar4f(ed::StyleVar varIndex, const ImVec4 *value)
    {
        ed::PushStyleVar(varIndex, *value);
    }

    void zine_PopStyleVar(int count)
    {
        ed::PopStyleVar(count);
    }

    // Selection

    bool zine_HasSelectionChanged()
    {
        return ed::HasSelectionChanged();
    }

    int zine_GetSelectedObjectCount()
    {
        return ed::GetSelectedObjectCount();
    }

    void zine_ClearSelection()
    {
        return ed::ClearSelection();
    }

    int zine_GetSelectedNodes(ed::NodeId *nodes, int size)
    {
        return ed::GetSelectedNodes(nodes, size);
    }

    int zine_GetSelectedLinks(ed::LinkId *links, int size)
    {
        return ed::GetSelectedLinks(links, size);
    }
}
