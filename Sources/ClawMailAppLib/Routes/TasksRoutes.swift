import Foundation
import Hummingbird
import ClawMailCore

// MARK: - TasksRoutes

/// Route group for task operations under `/api/v1/tasks`.
enum TasksRoutes {

    static func register(on router: Router<BasicRequestContext>, orchestrator: AccountOrchestrator) {
        let group = router.group("api/v1/tasks")

        // GET /api/v1/tasks/task-lists — list task lists
        group.get("task-lists") { request, context -> Response in
            do {
                let account = try requireQueryParam(request.uri.queryParameters, "account")
                let taskLists = try await orchestrator.listTaskLists(account: account)
                return jsonResponse(taskLists)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // GET /api/v1/tasks — list tasks
        group.get { request, context -> Response in
            do {
                let qp = request.uri.queryParameters
                let account = try requireQueryParam(qp, "account")
                let taskList = optionalQueryParam(qp, "taskList")
                let includeCompleted = boolQueryParam(qp, "includeCompleted", default: false)
                let tasks = try await orchestrator.listTasks(
                    account: account,
                    taskList: taskList,
                    includeCompleted: includeCompleted
                )
                return jsonResponse(tasks)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // POST /api/v1/tasks — create task
        group.post { request, context -> Response in
            do {
                let body = try await decodeBody(CreateTaskRequest.self, from: request, context: context)
                let task = try await orchestrator.createTask(account: body.account, body, interface: .rest)
                return jsonResponse(task, status: .created)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // PUT /api/v1/tasks/:taskId — update task
        group.put(":taskId") { request, context -> Response in
            do {
                guard let taskId = context.parameters.get("taskId") else {
                    return badRequestResponse("Missing taskId")
                }
                let body = try await decodeBody(UpdateTaskRequest.self, from: request, context: context)
                let task = try await orchestrator.updateTask(
                    account: body.account,
                    id: taskId,
                    body,
                    interface: .rest
                )
                return jsonResponse(task)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // DELETE /api/v1/tasks/:taskId — delete task
        group.delete(":taskId") { request, context -> Response in
            do {
                let account = try requireQueryParam(request.uri.queryParameters, "account")
                guard let taskId = context.parameters.get("taskId") else {
                    return badRequestResponse("Missing taskId")
                }
                try await orchestrator.deleteTask(account: account, id: taskId, interface: .rest)
                return jsonResponse(["ok": true])
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }
    }
}
