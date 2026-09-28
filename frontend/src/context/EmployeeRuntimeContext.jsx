import { createContext, useContext } from 'react';

export const ACTIVE_QUEUE_STATUSES = [
  'assigned',
  'accepted',
  'customer_approved',
  'repair_authorized',
  'on_the_way',
  'en_route',
  'arrived',
  'in_progress',
  'in_service',
  'inspection',
  'proof_submitted',
  'quotation_created',
  'quotation_pending_approval',
  'quotation_sent',
  'inspection_completed',
];

export const EmployeeRuntimeContext = createContext(null);

export function useEmployeeRuntime() {
  const context = useContext(EmployeeRuntimeContext);
  if (!context) {
    throw new Error('useEmployeeRuntime must be used within an EmployeeRuntimeProvider');
  }
  return context;
}
